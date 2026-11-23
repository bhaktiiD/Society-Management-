"""Visitor gate passes: a resident pre-approves a visitor, the guard verifies
the code at the gate and checks the visitor in without waiting for approval."""
import re
import secrets
from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from deps import (
    SocietyContext,
    audit,
    current_flat_memberships,
    current_residents_of_flat,
    current_user,
    get_db,
    require_guard,
    user_flat_ids,
)
from models import Flat, GatePass, GuestRequest, User
from push import notify_users

router = APIRouter(tags=["gate-passes"])

ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
CODE_LEN = 8
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
NOT_FOUND = "We could not find that pass. Please check the code."


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _gen_code() -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(CODE_LEN))


def _status(p: GatePass) -> str:
    if p.status == "active" and p.valid_until_date < date.today():
        return "expired"
    return p.status


def _names(db: Session, flat_id: int) -> list[str]:
    ids = current_residents_of_flat(db, flat_id)
    if not ids:
        return []
    rows = db.query(User.full_name).filter(User.id.in_(ids)).order_by(User.full_name).all()
    return [r[0] for r in rows]


def _ser(p: GatePass, flat_number: str, creator_name: str | None, *, code: bool = True) -> dict:
    d = {
        "id": p.id,
        "visitor_name": p.visitor_name,
        "visitor_phone": p.visitor_phone,
        "visitor_email": p.visitor_email,
        "purpose": p.purpose,
        "vehicle_number": p.vehicle_number,
        "visit_date": p.visit_date.isoformat(),
        "valid_until": p.valid_until_date.isoformat(),
        "valid_days": p.valid_days,
        "status": _status(p),
        "flat_number": flat_number,
        "created_by_name": creator_name,
        "created_at": p.created_at.isoformat() if p.created_at else None,
        "used_at": p.used_at.isoformat() if p.used_at else None,
    }
    if code:
        d["pass_code"] = p.pass_code
    return d


def _ser_db(db: Session, p: GatePass, **kw) -> dict:
    flat = db.get(Flat, p.flat_id)
    creator = db.get(User, p.created_by)
    return _ser(p, flat.flat_number, creator.full_name if creator else None, **kw)


def _invalid_reason(p: GatePass) -> str | None:
    if p.status == "used":
        return "This pass was already used."
    if p.status == "cancelled":
        return "This pass was cancelled."
    today = date.today()
    if p.valid_until_date < today:
        return "This pass has expired."
    if p.visit_date > today:
        return f"This pass is for {p.visit_date.isoformat()}."
    return None


# -------------------------------------------------------------- resident
class PassIn(BaseModel):
    visitor_name: str
    visitor_phone: str
    visitor_email: str
    purpose: str | None = None
    vehicle_number: str | None = None
    visit_date: date
    valid_days: int = 1
    flat_id: int | None = None


@router.post("/passes", status_code=201)
def create_pass(body: PassIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    ms = [m for m in current_flat_memberships(db, user.id) if m.is_resident]
    if not ms:
        raise HTTPException(403, "Only residents can create gate passes.")
    flat_ids = sorted({m.flat_id for m in ms})
    if body.flat_id is not None:
        if body.flat_id not in flat_ids:
            raise HTTPException(403, "Only residents can create gate passes.")
        flat_id = body.flat_id
    elif len(flat_ids) == 1:
        flat_id = flat_ids[0]
    else:
        raise HTTPException(422, "Please choose a flat.")

    name = body.visitor_name.strip()
    if not 2 <= len(name) <= 100:
        raise HTTPException(422, "Please enter the visitor's name (2 to 100 characters).")
    phone = re.sub(r"[\s-]", "", body.visitor_phone)
    if not re.fullmatch(r"\+?\d{10,15}", phone):
        raise HTTPException(422, "Please enter a valid phone number.")
    email = body.visitor_email.strip().lower()
    if len(email) > 150 or not _EMAIL_RE.match(email):
        raise HTTPException(422, "Please enter a valid email address.")
    purpose = (body.purpose or "").strip() or None
    if purpose and len(purpose) > 100:
        raise HTTPException(422, "Purpose is too long.")
    vehicle = (body.vehicle_number or "").strip().upper() or None
    if vehicle and len(vehicle) > 20:
        raise HTTPException(422, "Vehicle number is too long.")
    today = date.today()
    if not today <= body.visit_date <= today + timedelta(days=30):
        raise HTTPException(422, "Visit date must be within the next 30 days.")
    if not 1 <= body.valid_days <= 7:
        raise HTTPException(422, "A pass can be valid for 1 to 7 days.")

    flat = db.get(Flat, flat_id)
    p = None
    for _ in range(10):
        p = GatePass(
            society_id=flat.society_id,
            flat_id=flat_id,
            created_by=user.id,
            visitor_name=name,
            visitor_phone=phone,
            visitor_email=email,
            purpose=purpose,
            vehicle_number=vehicle,
            visit_date=body.visit_date,
            valid_days=body.valid_days,
            valid_until_date=body.visit_date + timedelta(days=body.valid_days - 1),
            pass_code=_gen_code(),
        )
        db.add(p)
        try:
            db.flush()
            break
        except IntegrityError:
            db.rollback()
            p = None
    if p is None:
        raise HTTPException(503, "Could not create the pass. Please try again.")
    audit(db, user, flat.society_id, "gate_pass.created", "gate_pass", p.id)
    db.commit()
    db.refresh(p)
    return _ser_db(db, p)


@router.get("/passes")
def list_passes(user: User = Depends(current_user), db: Session = Depends(get_db)):
    flat_ids = user_flat_ids(db, user.id, only_residents=True)
    if not flat_ids:
        return []
    since = date.today() - timedelta(days=60)
    rows = (
        db.query(GatePass, Flat.flat_number, User.full_name)
        .join(Flat, Flat.id == GatePass.flat_id)
        .join(User, User.id == GatePass.created_by)
        .filter(GatePass.flat_id.in_(flat_ids), GatePass.valid_until_date >= since)
        .order_by(GatePass.created_at.desc(), GatePass.id.desc())
        .all()
    )
    return [_ser(p, fn, cn) for p, fn, cn in rows]


@router.post("/passes/{pass_id}/cancel")
def cancel_pass(pass_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    p = db.get(GatePass, pass_id)
    if p is None or (
        p.created_by != user.id and p.flat_id not in user_flat_ids(db, user.id, only_residents=True)
    ):
        raise HTTPException(404, "We could not find that pass.")
    res = db.execute(
        update(GatePass).where(GatePass.id == pass_id, GatePass.status == "active").values(status="cancelled")
    )
    if res.rowcount == 0:
        db.rollback()
        db.refresh(p)
        if p.status == "used":
            raise HTTPException(409, "This pass was already used.")
        return _ser_db(db, p)  # already cancelled: idempotent
    audit(db, user, p.society_id, "gate_pass.cancelled", "gate_pass", pass_id)
    db.commit()
    db.refresh(p)
    return _ser_db(db, p)


# ----------------------------------------------------------------- guard
class VerifyIn(BaseModel):
    code: str


@router.post("/guard/passes/verify")
def verify_pass(body: VerifyIn, ctx: SocietyContext = Depends(require_guard), db: Session = Depends(get_db)):
    code = body.code.strip().upper()
    p = db.query(GatePass).filter(GatePass.society_id == ctx.society_id, GatePass.pass_code == code).first()
    if p is None:
        raise HTTPException(404, NOT_FOUND)
    reason = _invalid_reason(p)
    out = _ser_db(db, p)
    out["owner_names"] = _names(db, p.flat_id)
    return {"pass": out, "valid": reason is None, "reason": reason}


@router.post("/guard/passes/{pass_id}/check-in")
def pass_check_in(pass_id: int, ctx: SocietyContext = Depends(require_guard), db: Session = Depends(get_db)):
    today = date.today()
    now = _now()
    res = db.execute(
        update(GatePass)
        .where(
            GatePass.id == pass_id,
            GatePass.society_id == ctx.society_id,
            GatePass.status == "active",
            GatePass.visit_date <= today,
            GatePass.valid_until_date >= today,
        )
        .values(status="used", used_at=now)
    )
    if res.rowcount == 0:
        db.rollback()
        p = db.get(GatePass, pass_id)
        if p is None or p.society_id != ctx.society_id:
            raise HTTPException(404, NOT_FOUND)
        raise HTTPException(409, _invalid_reason(p) or "This pass cannot be used.")
    p = db.get(GatePass, pass_id)
    g = GuestRequest(
        society_id=p.society_id,
        flat_id=p.flat_id,
        guest_name=p.visitor_name,
        guest_phone=p.visitor_phone,
        purpose="Gate pass",
        status="checked_in",
        created_by=ctx.user.id,
        expires_at=now,
        decided_by=p.created_by,
        decided_at=now,
        checked_in_at=now,
    )
    db.add(g)
    db.flush()
    p.guest_request_id = g.id
    audit(db, ctx.user, ctx.society_id, "gate_pass.checked_in", "gate_pass", pass_id)
    db.commit()
    db.refresh(p)
    recipients = list({p.created_by, *current_residents_of_flat(db, p.flat_id)})
    notify_users(
        db, recipients, "Visitor arrived", f"{p.visitor_name} has arrived at the gate",
        {"type": "gate_pass_arrived", "gate_pass_id": p.id},
    )
    return _ser_db(db, p)


@router.get("/guard/passes/today")
def passes_today(ctx: SocietyContext = Depends(require_guard), db: Session = Depends(get_db)):
    today = date.today()
    rows = (
        db.query(GatePass, Flat.flat_number, User.full_name)
        .join(Flat, Flat.id == GatePass.flat_id)
        .join(User, User.id == GatePass.created_by)
        .filter(
            GatePass.society_id == ctx.society_id,
            GatePass.status == "active",
            GatePass.visit_date <= today,
            GatePass.valid_until_date >= today,
        )
        .order_by(GatePass.created_at.desc())
        .all()
    )
    return [_ser(p, fn, cn, code=False) for p, fn, cn in rows]
