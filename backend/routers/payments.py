"""PayEngine HTTP surface.

Flow: create intent+order -> Flutter checkout -> /verify (UX signal, still
server-verified) and/or webhook -> both call record_verified_payment().
"""
import json
import logging
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

import gateway
from deps import co_owner_payable_flat_ids, current_user, get_db
from models import Charge, PaymentIntent, User, WebhookEvent
from payments_service import charge_balance_paise, charge_paid_paise, charge_status, record_verified_payment

log = logging.getLogger("societyos.payments")
router = APIRouter(tags=["payments"])


class IntentIn(BaseModel):
    charge_id: int
    amount_paise: int = Field(gt=0)
    idempotency_key: str = Field(min_length=8, max_length=64)


def _intent_response(intent: PaymentIntent) -> dict:
    return {
        "intent_id": intent.id,
        "order_id": intent.razorpay_order_id,
        "amount_paise": intent.amount_paise,
        "key_id": gateway.public_key_id(),
        "status": intent.status,
    }


@router.post("/payments/intents")
def create_intent(
    body: IntentIn, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    # Retry of the same client attempt -> same intent, no second order.
    existing = (
        db.query(PaymentIntent)
        .filter(PaymentIntent.user_id == user.id, PaymentIntent.idempotency_key == body.idempotency_key)
        .first()
    )
    if existing:
        return _intent_response(existing)

    charge = db.get(Charge, body.charge_id)
    # 404 (not 403) for charges that aren't yours: don't confirm they exist.
    if charge is None or (
        charge.responsible_user_id != user.id and charge.id not in co_owner_payable_flat_ids(db, user.id, [charge])
    ):
        raise HTTPException(404, "We could not find that bill.")

    balance = charge_balance_paise(db, charge)
    if balance <= 0:
        raise HTTPException(409, "This bill is already paid.")
    # Money already in flight on other open intents can't be paid twice.
    in_flight = (
        db.query(func.coalesce(func.sum(PaymentIntent.amount_paise), 0))
        .filter(PaymentIntent.charge_id == charge.id, PaymentIntent.status == "pending",
                PaymentIntent.created_at >= datetime.now(timezone.utc) - timedelta(minutes=10))
        .scalar()
    )
    balance -= int(in_flight)
    if balance <= 0:
        raise HTTPException(409, "A payment for this bill is already in progress.")
    if body.amount_paise > balance:
        raise HTTPException(422, f"The most you can pay for this bill is \u20b9{balance // 100}.{balance % 100:02d}.")

    intent = PaymentIntent(
        charge_id=charge.id,
        user_id=user.id,
        amount_paise=body.amount_paise,  # validated against server-side balance
        idempotency_key=body.idempotency_key,
        status="created",
    )
    db.add(intent)
    try:
        db.flush()
    except IntegrityError:  # concurrent duplicate of the same key
        db.rollback()
        existing = (
            db.query(PaymentIntent)
            .filter(PaymentIntent.user_id == user.id, PaymentIntent.idempotency_key == body.idempotency_key)
            .one()
        )
        return _intent_response(existing)
    db.commit()  # persist our attempt BEFORE talking to the gateway

    try:
        order = gateway.create_order(
            intent.amount_paise, f"intent_{intent.id}", {"intent_id": str(intent.id), "charge_id": str(charge.id)}
        )
    except Exception:
        log.exception("Razorpay order creation failed")
        intent.status = "failed"
        db.commit()
        raise HTTPException(502, "Payment gateway unavailable, please try again")

    intent.razorpay_order_id = order["id"]
    intent.status = "pending"
    db.commit()
    return _intent_response(intent)


class VerifyIn(BaseModel):
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str


def _own_intent_by_order(db: Session, user: User, order_id: str) -> PaymentIntent:
    intent = (
        db.query(PaymentIntent)
        .filter(PaymentIntent.razorpay_order_id == order_id, PaymentIntent.user_id == user.id)
        .first()
    )
    if intent is None:
        raise HTTPException(404, "We could not find that payment.")
    return intent


def _confirm_with_gateway(db: Session, intent: PaymentIntent, payment_id: str) -> bool:
    """Ask Razorpay itself; trust nothing the client said about status/amount."""
    p = gateway.fetch_payment(payment_id)
    if p.get("order_id") != intent.razorpay_order_id:
        return False
    if p.get("status") != "captured":
        return False
    if int(p.get("amount", 0)) != intent.amount_paise:
        log.error("Amount mismatch for intent %s", intent.id)
        return False
    record_verified_payment(db, intent, payment_id, int(p["amount"]))
    return True


@router.post("/payments/verify")
def verify_payment(
    body: VerifyIn, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    intent = _own_intent_by_order(db, user, body.razorpay_order_id)
    if not gateway.verify_checkout_signature(
        body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature
    ):
        raise HTTPException(400, "We could not verify this payment. If money was deducted, it will show up within a few minutes.")
    try:
        confirmed = _confirm_with_gateway(db, intent, body.razorpay_payment_id)
    except HTTPException:
        raise
    except Exception:
        log.exception("Gateway confirmation failed")
        # Not a failure of the payment itself; the app will poll /status.
        confirmed = False
    db.refresh(intent)
    return {"status": "paid" if confirmed or intent.status == "paid" else "pending"}


@router.get("/payments/intents/{intent_id}/status")
def intent_status(
    intent_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    """Recovery endpoint: safe to call after an app crash or lost response.
    Reconciles an uncertain attempt against the gateway."""
    intent = db.get(PaymentIntent, intent_id)
    if intent is None or intent.user_id != user.id:
        raise HTTPException(404, "We could not find that payment.")

    if intent.status in ("created", "pending") and intent.razorpay_order_id:
        try:
            for p in gateway.order_payments(intent.razorpay_order_id):
                if p.get("status") == "captured" and int(p.get("amount", 0)) == intent.amount_paise:
                    record_verified_payment(db, intent, p["id"], int(p["amount"]))
                    break
        except Exception:
            log.exception("Reconciliation failed")
        db.refresh(intent)

    charge = db.get(Charge, intent.charge_id)
    paid = charge_paid_paise(db, charge.id)
    return {
        "intent_id": intent.id,
        "status": intent.status,
        "charge_id": charge.id,
        "charge_status": charge_status(charge.amount_paise, paid),
        "balance_paise": charge.amount_paise - paid,
    }


@router.post("/webhooks/razorpay")
async def razorpay_webhook(
    request: Request,
    x_razorpay_signature: str = Header(default=""),
    x_razorpay_event_id: str = Header(default=""),
    db: Session = Depends(get_db),
):
    raw = await request.body()
    if not gateway.verify_webhook_signature(raw, x_razorpay_signature):
        raise HTTPException(400, "Invalid webhook signature")
    try:
        payload = json.loads(raw)
    except ValueError:
        raise HTTPException(400, "Malformed payload")

    event_id = x_razorpay_event_id or f"noid-{uuid.uuid4()}"
    event = WebhookEvent(
        event_id=event_id, event_type=str(payload.get("event", ""))[:60], payload=payload
    )
    db.add(event)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        existing = db.query(WebhookEvent).filter(WebhookEvent.event_id == event_id).one()
        if existing.processed_at is not None:
            return {"status": "duplicate"}  # retried delivery: already handled
        # Stored earlier but processing never finished (crash/timeout): do it now.
        event = existing

    entity = ((payload.get("payload") or {}).get("payment") or {}).get("entity") or {}
    order_id = entity.get("order_id")
    payment_id = entity.get("id")
    intent = (
        db.query(PaymentIntent).filter(PaymentIntent.razorpay_order_id == order_id).first()
        if order_id
        else None
    )
    if intent is not None and payment_id:
        if payload.get("event") in ("payment.captured", "order.paid"):
            if int(entity.get("amount", 0)) == intent.amount_paise:
                record_verified_payment(db, intent, payment_id, int(entity["amount"]))
            else:
                log.error("Webhook amount mismatch for intent %s", intent.id)
        elif payload.get("event") == "payment.failed" and intent.status != "paid":
            intent.status = "failed"

    event.processed_at = datetime.now(timezone.utc)
    db.commit()
    return {"status": "ok"}
