"""GateGuard: guest entry approval, check-in, check-out.

Rules (architecture doc): only CURRENT registered occupants may approve; the
first valid decision wins atomically; approval expires; check-in needs an
unexpired approval; check-out is idempotent. No stay-duration monitoring.
"""
import os
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import update
from sqlalchemy.orm import Session

from deps import (
    SocietyContext,
    audit,
    current_residents_of_flat,
    current_user,
    get_db,
    require_guard,
    user_flat_ids,
)
from models import Flat, GuestRequest, User
from push import notify_users

router = APIRouter(tags=["gateguard"])

APPROVAL_TTL_MINUTES = int(os.getenv("GUEST_APPROVAL_TTL_MINUTES", "30"))


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _expire_stale(db: Session, **scope) -> None:
    """Lazily flip overdue pending requests to expired."""
    q = update(GuestRequest).where(
        GuestRequest.status == "pending", GuestRequest.expires_at <= _now()
    )
    for col, val in scope.items():
        q = q.where(getattr(GuestRequest, col) == val)
    db.execute(q.values(status="expired"))
    db.commit()


def _ser(g: GuestRequest, flat_number: str | None = None) -> dict:
    return {
        "id": g.id,
        "flat_id": g.flat_id,
        "flat_number": flat_number,
        "guest_name": g.guest_name,
        "guest_phone": g.guest_phone,
        "purpose": g.purpose,
        "status": g.status,
        "created_at": g.created_at.isoformat(),
        "expires_at": g.expires_at.isoformat(),
        "checked_in_at": g.checked_in_at.isoformat() if g.checked_in_at else None,
        "checked_out_at": g.checked_out_at.isoformat() if g.checked_out_at else None,
    }


# ----------------------------------------------------------------- guard
class GuestIn(BaseModel):
    flat_number: str = Field(min_length=1, max_length=20)
    guest_name: str = Field(min_length=1, max_length=100)
    guest_phone: str | None = Field(default=None, max_length=20)
    purpose: str | None = Field(default=None, max_length=100)


@router.post("/guard/guests", status_code=201)
def request_entry(
    body: GuestIn, ctx: SocietyContext = Depends(require_guard), db: Session = Depends(get_db)
):
    flat = (
        db.query(Flat)
        .filter(Flat.society_id == ctx.society_id, Flat.flat_number == body.flat_number.strip())
        .first()
    )
    if flat is None:
        raise HTTPException(404, "That flat is not in your society.")

    approvers = current_residents_of_flat(db, flat.id)
    if not approvers:
        # Open architectural question (vacant flat): refuse rather than guess.
        raise HTTPException(422, "Nobody is registered in that flat to approve this visit.")

    g = GuestRequest(
        society_id=ctx.society_id,
        flat_id=flat.id,
        guest_name=body.guest_name.strip(),
        guest_phone=(body.guest_phone or "").strip() or None,
        purpose=(body.purpose or "").strip() or None,
        created_by=ctx.user.id,
        expires_at=_now() + timedelta(minutes=APPROVAL_TTL_MINUTES),
    )
    db.add(g)
    db.flush()
    audit(db, ctx.user, ctx.society_id, "guest.requested", "guest_request", g.id)
    db.commit()
    notify_users(
        db, approvers, "Guest at the gate",
        f"{g.guest_name} is asking to visit flat {flat.flat_number}",
        {"type": "guest_request", "guest_request_id": g.id},
    )
    return _ser(g, flat.flat_number)


@router.get("/guard/guests")
def guard_list(ctx: SocietyContext = Depends(require_guard), db: Session = Depends(get_db)):
    _expire_stale(db, society_id=ctx.society_id)
    rows = (
        db.query(GuestRequest, Flat.flat_number)
        .join(Flat, Flat.id == GuestRequest.flat_id)
        .filter(GuestRequest.society_id == ctx.society_id)
        .order_by(GuestRequest.created_at.desc())
        .limit(100)
        .all()
    )
    return [_ser(g, fn) for g, fn in rows]


@router.post("/guard/guests/{guest_id}/check-in")
def check_in(
    guest_id: int, ctx: SocietyContext = Depends(require_guard), db: Session = Depends(get_db)
):
    # Single-use + unexpired + same society, enforced in one conditional UPDATE.
    res = db.execute(
        update(GuestRequest)
        .where(
            GuestRequest.id == guest_id,
            GuestRequest.society_id == ctx.society_id,
            GuestRequest.status == "approved",
            GuestRequest.expires_at > _now(),
        )
        .values(status="checked_in", checked_in_at=_now())
    )
    if res.rowcount == 0:
        db.rollback()
        g = db.get(GuestRequest, guest_id)
        if g is None or g.society_id != ctx.society_id:
            raise HTTPException(404, "We could not find that visitor request.")
        raise HTTPException(409, "This guest cannot be checked in. It may not be approved yet, or the approval has expired.")
    audit(db, ctx.user, ctx.society_id, "guest.checked_in", "guest_request", guest_id)
    db.commit()
    return _ser(db.get(GuestRequest, guest_id))


@router.post("/guard/guests/{guest_id}/check-out")
def check_out(
    guest_id: int, ctx: SocietyContext = Depends(require_guard), db: Session = Depends(get_db)
):
    g = db.get(GuestRequest, guest_id)
    if g is None or g.society_id != ctx.society_id:
        raise HTTPException(404, "We could not find that visitor request.")
    if g.status == "checked_out":
        return _ser(g)  # idempotent: repeating checkout is harmless
    res = db.execute(
        update(GuestRequest)
        .where(GuestRequest.id == guest_id, GuestRequest.status == "checked_in")
        .values(status="checked_out", checked_out_at=_now(), checked_out_by=ctx.user.id)
    )
    if res.rowcount == 0:
        db.rollback()
        db.refresh(g)
        if g.status == "checked_out":
            return _ser(g)
        raise HTTPException(409, "This guest is not checked in.")
    audit(db, ctx.user, ctx.society_id, "guest.checked_out", "guest_request", guest_id)
    db.commit()
    return _ser(db.get(GuestRequest, guest_id))


# -------------------------------------------------------------- resident
@router.get("/guests/pending")
def my_pending_guests(user: User = Depends(current_user), db: Session = Depends(get_db)):
    flat_ids = user_flat_ids(db, user.id, only_residents=True)
    if not flat_ids:
        return []
    _expire_stale(db)
    rows = (
        db.query(GuestRequest, Flat.flat_number)
        .join(Flat, Flat.id == GuestRequest.flat_id)
        .filter(GuestRequest.flat_id.in_(flat_ids), GuestRequest.status == "pending")
        .order_by(GuestRequest.created_at.desc())
        .all()
    )
    return [_ser(g, fn) for g, fn in rows]


@router.get("/guests/history")
def my_guest_history(user: User = Depends(current_user), db: Session = Depends(get_db)):
    flat_ids = user_flat_ids(db, user.id, only_residents=True)
    if not flat_ids:
        return []
    rows = (
        db.query(GuestRequest, Flat.flat_number)
        .join(Flat, Flat.id == GuestRequest.flat_id)
        .filter(GuestRequest.flat_id.in_(flat_ids))
        .order_by(GuestRequest.created_at.desc())
        .limit(50)
        .all()
    )
    return [_ser(g, fn) for g, fn in rows]


class DecisionIn(BaseModel):
    approve: bool


@router.post("/guests/{guest_id}/decision")
def decide(
    guest_id: int,
    body: DecisionIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    g = db.get(GuestRequest, guest_id)
    # Not a current occupant of that flat (incl. non-resident owners and former
    # tenants) => indistinguishable from "does not exist".
    if g is None or g.flat_id not in user_flat_ids(db, user.id, only_residents=True):
        raise HTTPException(404, "We could not find that visitor request.")

    # First valid decision wins: only a still-pending, unexpired row updates.
    res = db.execute(
        update(GuestRequest)
        .where(
            GuestRequest.id == guest_id,
            GuestRequest.status == "pending",
            GuestRequest.expires_at > _now(),
        )
        .values(
            status="approved" if body.approve else "denied",
            decided_by=user.id,
            decided_at=_now(),
        )
    )
    if res.rowcount == 0:
        db.rollback()
        db.refresh(g)
        raise HTTPException(409, "Someone has already answered this request, or it has expired.")
    audit(
        db, user, g.society_id,
        "guest.approved" if body.approve else "guest.denied",
        "guest_request", guest_id, {"method": "app"},
    )
    db.commit()
    notify_users(
        db, [g.created_by], "Guest decision",
        f"{g.guest_name}: {'approved' if body.approve else 'denied'}",
        {"type": "guest_decision", "guest_request_id": g.id},
    )
    return _ser(db.get(GuestRequest, guest_id))
