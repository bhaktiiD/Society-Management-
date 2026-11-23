"""Community hall booking: custom time ranges on a date, no overlapping confirmed bookings.

Times are society-local wall-clock. Overlap is prevented by the exclusion constraint
ex_booking_no_overlap; the DB is the source of truth (IntegrityError -> 409),
pre-checks are only UX.
"""
import re
from datetime import date, datetime, time, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import case, or_, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from deps import (
    SocietyContext,
    audit,
    current_flat_memberships,
    current_user,
    get_db,
    guard_society_ids,
    require_secretary,
    secretary_society_ids,
)
from models import Amenity, Booking, Flat, FlatMembership, User
from push import notify_users

router = APIRouter(tags=["bookings"])

MAX_DAYS_AHEAD = 90
OPEN_TIME = time(8, 0)
CLOSE_TIME = time(22, 0)
STEP_MINUTES = 30
MIN_MINUTES = 60
MAX_MINUTES = 8 * 60
DEFAULT_NAME = "Community Hall"
DEFAULT_DESC = "Open daily 8 AM - 10 PM. Book any time range."
OVERLAP_MSG = "This time overlaps another confirmed booking. Ask the resident to pick a new time."
_HHMM = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")


def slot_label_for(start_hour: int) -> str:
    """Legacy label kept populated for old clients/data."""
    return "morning" if start_hour < 13 else "evening"


def _fmt_time(t) -> str:
    h12 = t.hour % 12 or 12
    suffix = "AM" if t.hour < 12 else "PM"
    return f"{h12} {suffix}" if t.minute == 0 else f"{h12}:{t.minute:02d} {suffix}"


def time_label(start: datetime, end: datetime) -> str:
    return f"{_fmt_time(start)} - {_fmt_time(end)}"


def _parse_hhmm(v: str) -> time:
    m = _HHMM.match(v or "")
    if not m:
        raise HTTPException(422, "Please enter times as HH:MM, for example 21:00.")
    return time(int(m.group(1)), int(m.group(2)))


def validate_range(d: date, start_s: str, end_s: str) -> tuple[datetime, datetime]:
    st, en = _parse_hhmm(start_s), _parse_hhmm(end_s)
    if st < OPEN_TIME or en > CLOSE_TIME or st >= CLOSE_TIME or en <= OPEN_TIME:
        raise HTTPException(422, "The hall is open from 8 AM to 10 PM.")
    if st.minute % STEP_MINUTES or en.minute % STEP_MINUTES:
        raise HTTPException(422, "Please choose times on the hour or half hour.")
    start, end = datetime.combine(d, st), datetime.combine(d, en)
    mins = (end - start).total_seconds() / 60
    if mins < MIN_MINUTES:
        raise HTTPException(422, "Bookings must be at least 1 hour.")
    if mins > MAX_MINUTES:
        raise HTTPException(422, "Bookings can be at most 8 hours.")
    if start <= datetime.now():
        raise HTTPException(422, "Please pick a start time in the future.")
    return start, end


def _overlap(start: datetime, end: datetime):
    return (Booking.start_at < end, Booking.end_at > start)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _caller_society_id(db: Session, user: User) -> int:
    ms = current_flat_memberships(db, user.id)
    if ms:
        return ms[0].flat.society_id
    ids = secretary_society_ids(db, user.id) or guard_society_ids(db, user.id)
    if not ids:
        raise HTTPException(403, "You are not part of a society yet.")
    return ids[0]


def _amenity_in_society(db: Session, amenity_id: int, society_id: int) -> Amenity:
    a = db.get(Amenity, amenity_id)
    if a is None or a.society_id != society_id:
        raise HTTPException(404, "We could not find that facility.")
    return a


def _ser_amenity(a: Amenity) -> dict:
    return {"id": a.id, "name": a.name, "description": a.description, "active": a.active}


def _ser_booking(b: Booking, amenity_name, flat_number, booker_name=None) -> dict:
    return {
        "id": b.id,
        "amenity_id": b.amenity_id,
        "amenity_name": amenity_name,
        "flat_id": b.flat_id,
        "flat_number": flat_number,
        "booked_by": str(b.booked_by),
        "booker_name": booker_name,
        "date": b.booking_date.isoformat(),
        "start_time": b.start_at.strftime("%H:%M"),
        "end_time": b.end_at.strftime("%H:%M"),
        "time_label": time_label(b.start_at, b.end_at),
        "slot": b.slot,
        "purpose": b.purpose,
        "status": b.status,
        "admin_note": b.admin_note,
        "decided_at": b.decided_at.isoformat() if b.decided_at else None,
        "created_at": b.created_at.isoformat() if b.created_at else None,
    }


# --------------------------------------------------------------- amenities
@router.get("/amenities")
def list_amenities(user: User = Depends(current_user), db: Session = Depends(get_db)):
    sid = _caller_society_id(db, user)

    def fetch():
        return db.query(Amenity).filter(Amenity.society_id == sid).order_by(Amenity.id).all()

    rows = fetch()
    if not rows:
        try:
            db.add(Amenity(society_id=sid, name=DEFAULT_NAME, description=DEFAULT_DESC))
            db.commit()
        except IntegrityError:
            db.rollback()
        rows = fetch()
    return [_ser_amenity(a) for a in rows]


@router.get("/amenities/{amenity_id}/availability")
def availability(
    amenity_id: int,
    days: int = Query(30, ge=1, le=90),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    sid = _caller_society_id(db, user)
    _amenity_in_society(db, amenity_id, sid)
    start = date.today()
    end = start + timedelta(days=days - 1)
    busy: dict = {}
    for b in (
        db.query(Booking)
        .filter(
            Booking.amenity_id == amenity_id,
            Booking.status == "confirmed",
            Booking.booking_date >= start,
            Booking.booking_date <= end,
        )
        .order_by(Booking.start_at)
    ):
        busy.setdefault(b.booking_date, []).append(
            {"start": b.start_at.strftime("%H:%M"), "end": b.end_at.strftime("%H:%M")}
        )
    out = []
    for i in range(days):
        d = start + timedelta(days=i)
        out.append(
            {
                "date": d.isoformat(),
                "busy": busy.get(d, []),
                "open": OPEN_TIME.strftime("%H:%M"),
                "close": CLOSE_TIME.strftime("%H:%M"),
            }
        )
    return out


# ---------------------------------------------------------------- bookings
class BookingIn(BaseModel):
    amenity_id: int
    date: date
    start_time: str
    end_time: str
    purpose: str | None = Field(default=None, max_length=100)
    flat_id: int | None = None
    replaces_booking_id: int | None = None


@router.post("/bookings", status_code=201)
def create_booking(
    body: BookingIn, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    resident = [m for m in current_flat_memberships(db, user.id) if m.is_resident]
    if not resident:
        raise HTTPException(403, "Only residents can book the hall.")
    if body.flat_id is None:
        membership = resident[0]
    else:
        membership = next((m for m in resident if m.flat_id == body.flat_id), None)
        if membership is None:
            raise HTTPException(404, "Flat not found")
    flat = membership.flat
    amenity = db.get(Amenity, body.amenity_id)
    if amenity is None or amenity.society_id != flat.society_id or not amenity.active:
        raise HTTPException(404, "We could not find that facility.")
    today = date.today()
    if body.date < today or body.date > today + timedelta(days=MAX_DAYS_AHEAD):
        raise HTTPException(422, f"Please pick a date within the next {MAX_DAYS_AHEAD} days.")

    start, end = validate_range(body.date, body.start_time, body.end_time)
    same_amenity = (Booking.amenity_id == amenity.id, *_overlap(start, end))
    if db.query(Booking.id).filter(*same_amenity, Booking.status == "confirmed").first():
        raise HTTPException(409, "That time is already booked. Please pick another time.")
    if (
        db.query(Booking.id)
        .filter(*same_amenity, Booking.booked_by == user.id, Booking.status.in_(("pending", "confirmed")))
        .first()
    ):
        raise HTTPException(409, "You already have a request for that time.")

    purpose = (body.purpose or "").strip() or None
    b = Booking(
        amenity_id=amenity.id,
        flat_id=flat.id,
        booked_by=user.id,
        booking_date=body.date,
        slot=slot_label_for(start.hour),
        start_at=start,
        end_at=end,
        purpose=purpose,
        status="pending",
    )
    db.add(b)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "That time is already booked. Please pick another time.")
    if body.replaces_booking_id is not None:
        old = db.get(Booking, body.replaces_booking_id)
        if old is not None and old.booked_by == user.id and old.status == "reschedule":
            old.status = "cancelled"
            old.cancelled_at = _now()
            old.cancelled_by = user.id
    audit(
        db, user, flat.society_id, "booking.created", "booking", b.id,
        {"date": body.date.isoformat(), "time": time_label(start, end)},
    )
    db.commit()
    db.refresh(b)
    return _ser_booking(b, amenity.name, flat.flat_number, user.full_name)


@router.get("/bookings/mine")
def my_bookings(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = (
        db.query(Booking, Amenity.name, Flat.flat_number)
        .join(Amenity, Amenity.id == Booking.amenity_id)
        .join(Flat, Flat.id == Booking.flat_id)
        .filter(Booking.booked_by == user.id)
        .order_by(Booking.booking_date.desc(), Booking.id.desc())
        .all()
    )
    return [_ser_booking(b, an, fn, user.full_name) for b, an, fn in rows]


def _cancel(
    db: Session, b: Booking, actor: User, society_id: int,
    from_statuses: tuple = ("confirmed",),
) -> bool:
    """Atomically <from_statuses> -> cancelled. True if this call did it."""
    res = db.execute(
        update(Booking)
        .where(Booking.id == b.id, Booking.status.in_(from_statuses))
        .values(status="cancelled", cancelled_at=_now(), cancelled_by=actor.id)
    )
    if res.rowcount:
        audit(db, actor, society_id, "booking.cancelled", "booking", b.id)
    db.commit()
    return bool(res.rowcount)


@router.delete("/bookings/{booking_id}")
def cancel_booking(
    booking_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    b = db.get(Booking, booking_id)
    if b is None or b.booked_by != user.id:
        raise HTTPException(404, "We could not find that booking.")
    if b.status in ("pending", "confirmed", "reschedule"):
        if b.booking_date < date.today():
            raise HTTPException(409, "Past bookings cannot be cancelled.")
        flat = db.get(Flat, b.flat_id)
        _cancel(db, b, user, flat.society_id, ("pending", "confirmed", "reschedule"))
    db.refresh(b)
    return {"id": b.id, "status": b.status}


# --------------------------------------------------------------- secretary
@router.get("/secretary/bookings")
def secretary_bookings(
    upcoming: bool = False,
    ctx: SocietyContext = Depends(require_secretary),
    db: Session = Depends(get_db),
):
    q = (
        db.query(Booking, Amenity.name, Flat.flat_number, User.full_name)
        .join(Amenity, Amenity.id == Booking.amenity_id)
        .join(Flat, Flat.id == Booking.flat_id)
        .join(User, User.id == Booking.booked_by)
        .filter(Amenity.society_id == ctx.society_id)
    )
    if upcoming:
        q = q.filter(Booking.booking_date >= date.today()).order_by(
            Booking.start_at, Booking.id
        )
    else:
        q = q.order_by(
            case((Booking.status == "pending", 0), else_=1),
            Booking.booking_date.desc(),
            Booking.id.desc(),
        )
    rows = q.all()
    if not rows:
        return []

    # Two lookups for the whole list, never per row.
    today = date.today()
    pairs = {(b.flat_id, b.booked_by) for b, *_ in rows}
    kinds: dict = {}
    for m in (
        db.query(FlatMembership)
        .filter(
            FlatMembership.flat_id.in_({p[0] for p in pairs}),
            FlatMembership.user_id.in_({p[1] for p in pairs}),
            FlatMembership.start_date <= today,
            or_(FlatMembership.end_date.is_(None), FlatMembership.end_date >= today),
        )
        .order_by(FlatMembership.id)
    ):
        kinds.setdefault((m.flat_id, m.user_id), m.kind)
    phones = dict(
        db.query(User.id, User.phone).filter(User.id.in_({p[1] for p in pairs})).all()
    )
    dates = [b.booking_date for b, *_ in rows]
    confirmed = (
        db.query(Booking.id, Booking.amenity_id, Booking.start_at, Booking.end_at)
        .filter(
            Booking.status == "confirmed",
            Booking.amenity_id.in_({b.amenity_id for b, *_ in rows}),
            Booking.booking_date >= min(dates),
            Booking.booking_date <= max(dates),
        )
        .all()
    )
    out = []
    for b, an, fn, bn in rows:
        d = _ser_booking(b, an, fn, bn)
        d["booker_kind"] = kinds.get((b.flat_id, b.booked_by))
        d["booker_phone"] = phones.get(b.booked_by) or None
        d["slot_taken"] = any(
            c.id != b.id and c.amenity_id == b.amenity_id
            and c.start_at < b.end_at and c.end_at > b.start_at
            for c in confirmed
        )
        out.append(d)
    return out


def _admin_booking(db: Session, booking_id: int, ctx: SocietyContext) -> Booking:
    b = db.get(Booking, booking_id)
    amenity = db.get(Amenity, b.amenity_id) if b else None
    if b is None or amenity.society_id != ctx.society_id:
        raise HTTPException(404, "We could not find that booking.")
    return b


def _decide(db: Session, b: Booking, ctx: SocietyContext, status: str, note, action: str) -> bool:
    """Atomic pending -> status. False if someone else handled it first."""
    res = db.execute(
        update(Booking)
        .where(Booking.id == b.id, Booking.status == "pending")
        .values(status=status, admin_note=note, decided_at=_now(), decided_by=ctx.user.id)
    )
    if not res.rowcount:
        db.rollback()
        return False
    audit(
        db, ctx.user, ctx.society_id, action, "booking", b.id,
        {"date": b.booking_date.isoformat(), "time": time_label(b.start_at, b.end_at)},
    )
    db.commit()
    return True


HANDLED = "This request was already handled."


@router.post("/secretary/bookings/{booking_id}/approve")
def secretary_approve(
    booking_id: int,
    ctx: SocietyContext = Depends(require_secretary),
    db: Session = Depends(get_db),
):
    b = _admin_booking(db, booking_id, ctx)
    if b.status != "pending":
        raise HTTPException(409, HANDLED)
    try:
        ok = _decide(db, b, ctx, "confirmed", None, "booking.approved")
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, OVERLAP_MSG)
    if not ok:
        raise HTTPException(409, HANDLED)
    notify_users(
        db, [b.booked_by], "Hall booking approved",
        f"Your booking on {b.booking_date.isoformat()}, {time_label(b.start_at, b.end_at)}, is confirmed.",
        {"type": "booking_approved", "booking_id": str(b.id)},
    )
    db.refresh(b)
    return {"id": b.id, "status": b.status}


class RescheduleIn(BaseModel):
    note: str | None = Field(default=None, max_length=300)


@router.post("/secretary/bookings/{booking_id}/reschedule")
def secretary_reschedule(
    booking_id: int,
    body: RescheduleIn | None = None,
    ctx: SocietyContext = Depends(require_secretary),
    db: Session = Depends(get_db),
):
    b = _admin_booking(db, booking_id, ctx)
    note = ((body.note if body else None) or "").strip()
    if b.status != "pending" or not _decide(db, b, ctx, "reschedule", note, "booking.rescheduled"):
        raise HTTPException(409, HANDLED)
    text = (
        f"The hall is already booked on {b.booking_date.isoformat()} at "
        f"{time_label(b.start_at, b.end_at)}. Please pick a new time."
    )
    if note:
        text += f" {note}"
    notify_users(
        db, [b.booked_by], "Please choose another date", text,
        {"type": "booking_reschedule", "booking_id": str(b.id)},
    )
    db.refresh(b)
    return {"id": b.id, "status": b.status}


class DeclineIn(BaseModel):
    reason: str | None = None


@router.post("/secretary/bookings/{booking_id}/decline")
def secretary_decline(
    booking_id: int,
    body: DeclineIn,
    ctx: SocietyContext = Depends(require_secretary),
    db: Session = Depends(get_db),
):
    reason = (body.reason or "").strip()
    if not 5 <= len(reason) <= 300:
        raise HTTPException(422, "Please give a reason between 5 and 300 characters.")
    b = _admin_booking(db, booking_id, ctx)
    if b.status != "pending" or not _decide(db, b, ctx, "declined", reason, "booking.declined"):
        raise HTTPException(409, HANDLED)
    notify_users(
        db, [b.booked_by], "Hall booking not approved",
        f"Your booking on {b.booking_date.isoformat()}, {time_label(b.start_at, b.end_at)}, "
        f"was not approved: {reason}",
        {"type": "booking_declined", "booking_id": str(b.id)},
    )
    db.refresh(b)
    return {"id": b.id, "status": b.status}


@router.post("/secretary/bookings/{booking_id}/cancel")
def secretary_cancel(
    booking_id: int,
    ctx: SocietyContext = Depends(require_secretary),
    db: Session = Depends(get_db),
):
    b = _admin_booking(db, booking_id, ctx)
    if b.status != "cancelled":
        if b.booking_date < date.today():
            raise HTTPException(409, "Past bookings cannot be cancelled.")
        if _cancel(db, b, ctx.user, ctx.society_id):
            notify_users(
                db,
                [b.booked_by],
                "Hall booking cancelled",
                f"Your booking on {b.booking_date.isoformat()}, "
                f"{time_label(b.start_at, b.end_at)}, was cancelled by the secretary.",
                {"type": "booking_cancelled", "booking_id": str(b.id)},
            )
    db.refresh(b)
    return {"id": b.id, "status": b.status}
