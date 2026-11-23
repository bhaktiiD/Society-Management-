"""Emergency (SOS) alerts: any society member can raise one, everyone else in
the society is pushed at once. Push is best-effort; the database is the truth."""
import logging
from datetime import date, datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field
from sqlalchemy import exists, literal, or_, select, union_all
from sqlalchemy.orm import Session, aliased

from deps import (
    audit,
    current_flat_memberships,
    current_user,
    get_db,
    secretary_society_ids,
)
from models import (
    Emergency,
    Flat,
    FlatMembership,
    GuardMembership,
    SocietyAdminMembership,
    User,
)
from push import notify_users

log = logging.getLogger("societyos.emergencies")
router = APIRouter(tags=["emergencies"])

KIND_LABEL = {"fire": "Fire", "medical": "Medical", "security": "Security", "other": "Emergency"}
DUPLICATE_WINDOW = timedelta(minutes=2)
ACTIVE_WINDOW = timedelta(hours=6)


class EmergencyIn(BaseModel):
    kind: Literal["fire", "medical", "security", "other"] = "other"
    message: str | None = Field(default=None, max_length=200)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _admin_guard_society(db: Session, user_id) -> int | None:
    """Society of an admin, else of a guard, in one query."""
    adm = select(SocietyAdminMembership.society_id.label("sid"), literal(1).label("p")).where(
        SocietyAdminMembership.user_id == user_id, SocietyAdminMembership.revoked_at.is_(None)
    )
    grd = select(GuardMembership.society_id.label("sid"), literal(2).label("p")).where(
        GuardMembership.user_id == user_id, GuardMembership.revoked_at.is_(None)
    )
    u = union_all(adm, grd).subquery()
    row = db.execute(select(u.c.sid).order_by(u.c.p).limit(1)).first()
    return row[0] if row else None


def _society_id(db: Session, user: User) -> int:
    ms = current_flat_memberships(db, user.id)
    if ms:
        return ms[0].flat.society_id
    sid = _admin_guard_society(db, user.id)
    if sid is None:
        raise HTTPException(403, "You are not part of a society yet.")
    return sid


def _query(db: Session, caller_id, *where, limit=None):
    """Emergencies with raiser name/phone/flat number/role in ONE query."""
    today = date.today()
    raiser = aliased(User)
    resolver = aliased(User)
    kind_sq = (
        select(FlatMembership.kind)
        .where(
            FlatMembership.user_id == Emergency.raised_by,
            FlatMembership.flat_id == Emergency.flat_id,
            FlatMembership.start_date <= today,
            or_(FlatMembership.end_date.is_(None), FlatMembership.end_date >= today),
        )
        .limit(1)
        .correlate(Emergency)
        .scalar_subquery()
    )
    is_admin = exists().where(
        SocietyAdminMembership.user_id == Emergency.raised_by,
        SocietyAdminMembership.society_id == Emergency.society_id,
        SocietyAdminMembership.revoked_at.is_(None),
    )
    is_guard = exists().where(
        GuardMembership.user_id == Emergency.raised_by,
        GuardMembership.society_id == Emergency.society_id,
        GuardMembership.revoked_at.is_(None),
    )
    q = (
        select(
            Emergency,
            raiser.full_name,
            raiser.phone,
            Flat.flat_number,
            resolver.full_name,
            kind_sq,
            is_admin,
            is_guard,
        )
        .join(raiser, raiser.id == Emergency.raised_by)
        .outerjoin(Flat, Flat.id == Emergency.flat_id)
        .outerjoin(resolver, resolver.id == Emergency.resolved_by)
        .where(*where)
        .order_by(Emergency.created_at.desc(), Emergency.id.desc())
    )
    if limit:
        q = q.limit(limit)
    out = []
    for e, name, phone, flat_no, res_name, kind, adm, grd in db.execute(q).all():
        if kind:
            role = kind.capitalize()
        elif adm:
            role = "Secretary"
        elif grd:
            role = "Guard"
        else:
            role = "Owner"
        out.append(
            {
                "id": e.id,
                "kind": e.kind,
                "kind_label": KIND_LABEL[e.kind],
                "message": e.message,
                "raised_by_name": name,
                "flat_number": flat_no,
                "phone": phone,
                "role_label": role,
                "created_at": e.created_at,
                "resolved_at": e.resolved_at,
                "resolved_by_name": res_name,
                "mine": e.raised_by == caller_id,
            }
        )
    return out


def _one(db: Session, caller_id, emergency_id: int) -> dict:
    return _query(db, caller_id, Emergency.id == emergency_id)[0]


def _recipients(db: Session, society_id: int, exclude) -> list:
    today = date.today()
    flat_users = (
        select(FlatMembership.user_id)
        .join(Flat, Flat.id == FlatMembership.flat_id)
        .where(
            Flat.society_id == society_id,
            FlatMembership.start_date <= today,
            or_(FlatMembership.end_date.is_(None), FlatMembership.end_date >= today),
        )
    )
    admins = select(SocietyAdminMembership.user_id).where(
        SocietyAdminMembership.society_id == society_id,
        SocietyAdminMembership.revoked_at.is_(None),
    )
    guards = select(GuardMembership.user_id).where(
        GuardMembership.society_id == society_id, GuardMembership.revoked_at.is_(None)
    )
    ids = {r[0] for r in db.execute(union_all(flat_users, admins, guards)).all()}
    ids.discard(exclude)
    return list(ids)


@router.post("/emergencies")
def raise_emergency(
    body: EmergencyIn,
    response: Response,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    ms = current_flat_memberships(db, user.id)
    resident = next((m for m in ms if m.is_resident), None)
    if ms:
        society_id = ms[0].flat.society_id
    else:
        sid = _admin_guard_society(db, user.id)
        if sid is None:
            raise HTTPException(403, "You are not part of a society yet.")
        society_id = sid

    recent = (
        db.query(Emergency.id)
        .filter(
            Emergency.raised_by == user.id,
            Emergency.society_id == society_id,
            Emergency.resolved_at.is_(None),
            Emergency.created_at >= _now() - DUPLICATE_WINDOW,
        )
        .order_by(Emergency.created_at.desc())
        .first()
    )
    if recent:
        return _one(db, user.id, recent[0])

    flat = resident.flat if resident else None
    e = Emergency(
        society_id=society_id,
        raised_by=user.id,
        flat_id=flat.id if flat else None,
        kind=body.kind,
        message=(body.message or "").strip() or None,
    )
    db.add(e)
    db.flush()
    audit(db, user, society_id, "emergency.raised", "emergency", e.id, {"kind": e.kind})
    db.commit()
    response.status_code = 201
    result = _one(db, user.id, e.id)

    try:
        if flat:
            where = f"Flat {flat.flat_number} needs help"
        elif result["role_label"] == "Guard":
            where = "at the gate needs help"
        else:
            where = "from the office needs help"
        notify_users(
            db,
            _recipients(db, society_id, user.id),
            title=f"EMERGENCY - {KIND_LABEL[e.kind]}",
            body=f"{user.full_name}, {where}",
            data={
                "type": "emergency",
                "emergency_id": e.id,
                "flat_number": flat.flat_number if flat else "",
                "name": user.full_name,
                "phone": user.phone or "",
                "kind": e.kind,
            },
            urgent=True,
        )
    except Exception:
        log.exception("Emergency push failed")
    return result


@router.get("/emergencies/active")
def active_emergencies(user: User = Depends(current_user), db: Session = Depends(get_db)):
    society_id = _society_id(db, user)
    return _query(
        db,
        user.id,
        Emergency.society_id == society_id,
        Emergency.resolved_at.is_(None),
        Emergency.created_at >= _now() - ACTIVE_WINDOW,
    )


@router.post("/emergencies/{emergency_id}/resolve")
def resolve_emergency(
    emergency_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    society_id = _society_id(db, user)
    e = db.get(Emergency, emergency_id)
    if e is None or e.society_id != society_id:
        raise HTTPException(404, "We could not find that emergency.")
    if e.raised_by != user.id and society_id not in secretary_society_ids(db, user.id):
        raise HTTPException(403, "Only the person who raised it or the admin can resolve this.")
    if e.resolved_at is None:
        e.resolved_at = _now()
        e.resolved_by = user.id
        audit(db, user, society_id, "emergency.resolved", "emergency", e.id)
        db.commit()
    return _one(db, user.id, emergency_id)


@router.get("/secretary/emergencies")
def emergency_history(user: User = Depends(current_user), db: Session = Depends(get_db)):
    ids = secretary_society_ids(db, user.id)
    if not ids:
        raise HTTPException(403, "Only the society admin can do this.")
    return _query(db, user.id, Emergency.society_id == ids[0], limit=50)
