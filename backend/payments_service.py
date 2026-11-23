"""PayEngine core: the only place a verified payment becomes an allocation.

Invariants enforced here and by DB constraints:
* a gateway payment id is stored once (UNIQUE) and allocated at most once
  (UNIQUE on payment_allocations.gateway_payment_id);
* allocation never exceeds the charge's outstanding balance (charge row is
  locked FOR UPDATE for the duration of the transaction);
* the client callback is never trusted - callers must pass amounts/ids that
  were confirmed with the gateway (checkout signature + payment fetch, or a
  signed webhook).
"""
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from deps import audit
from models import (
    Charge,
    GatewayPayment,
    PaymentAllocation,
    PaymentIntent,
)


def charge_paid_paise(db: Session, charge_id: int) -> int:
    total = (
        db.query(func.coalesce(func.sum(PaymentAllocation.amount_paise), 0))
        .filter(PaymentAllocation.charge_id == charge_id)
        .scalar()
    )
    return int(total)


def charge_balance_paise(db: Session, charge: Charge) -> int:
    return charge.amount_paise - charge_paid_paise(db, charge.id)


def charge_status(amount: int, paid: int) -> str:
    if paid <= 0:
        return "outstanding"
    return "paid" if paid >= amount else "partial"


def record_verified_payment(
    db: Session, intent: PaymentIntent, razorpay_payment_id: str, amount_paise: int
) -> GatewayPayment:
    """Idempotently record a gateway-confirmed payment and allocate it.

    Safe to call any number of times, from the client-verify path, the webhook,
    or reconciliation, concurrently: they all converge on one GatewayPayment.
    """
    # Serialise everything touching this charge's balance.
    charge = (
        db.query(Charge).filter(Charge.id == intent.charge_id).with_for_update().one()
    )

    existing = (
        db.query(GatewayPayment)
        .filter(GatewayPayment.razorpay_payment_id == razorpay_payment_id)
        .first()
    )
    if existing:
        db.commit()
        return existing

    payment = GatewayPayment(
        intent_id=intent.id,
        razorpay_payment_id=razorpay_payment_id,
        amount_paise=amount_paise,
    )
    db.add(payment)
    try:
        db.flush()
    except IntegrityError:
        # Lost a race with a concurrent confirmation; use the winner's row.
        db.rollback()
        return (
            db.query(GatewayPayment)
            .filter(GatewayPayment.razorpay_payment_id == razorpay_payment_id)
            .one()
        )

    balance = charge.amount_paise - charge_paid_paise(db, charge.id)
    allocate = min(amount_paise, max(balance, 0))
    if allocate > 0:
        db.add(
            PaymentAllocation(
                gateway_payment_id=payment.id,
                charge_id=charge.id,
                amount_paise=allocate,
            )
        )
    intent.status = "paid"
    audit(
        db,
        None,
        charge.society_id,
        "payment.recorded",
        "gateway_payment",
        payment.id,
        {
            "razorpay_payment_id": razorpay_payment_id,
            "amount_paise": amount_paise,
            "allocated_paise": allocate,
            "unallocated_paise": amount_paise - allocate,
        },
    )
    db.commit()
    return payment
