"""Society meetings: the admin schedules, invited residents see them.

Invited = a person with a CURRENT flat membership in the society; audience
'owners' narrows that to members of kind 'owner'.
"""
from datetime import date, datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import and_, case, distinct, func, or_
from sqlalchemy.orm import Session

from deps import (
    SocietyContext,
    audit,
    current_flat_memberships,
    current_user,
    get_db,
    require_secretary,
)
from models import Flat, FlatMembership, Meeting, User
from push import notify_users

router = APIRouter(tags=["meetings"])

MAX_DAYS_AHEAD = 365
RECENT_DAYS = 30
LIMIT = 100


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _current_filter():
    today = date.today()
    return and_(
        FlatMembership.start_date <= today,
        or_(FlatMembership.end_date.is_(None), FlatMembership.end_date >= today),
    )


def _invited_ids(db: Session, society_id: int, audience: str) -> list:
    q = (
        db.query(FlatMembership.user_id)
        .join(Flat, Flat.id == FlatMembership.flat_id)
        .filter(Flat.society_id == society_id, _current_filter())
    )
    if audience == "owners":
        q = q.filter(FlatMembership.kind == "owner")
    return [r[0] for r in q.distinct().all()]


def _counts(db: Session, society_ids: set[int]) -> dict[int, tuple[int, int]]:
    """society_id -> (everyone_count, owners_count) in a single grouped query."""
    if not society_ids:
        return {}
    rows = (
        db.query(
            Flat.society_id,
            func.count(distinct(FlatMembership.user_id)),
            func.count(distinct(case((FlatMembership.kind == "owner", FlatMembership.user_id)))),
        )
        .join(Flat, Flat.id == FlatMembership.flat_id)
        .filter(Flat.society_id.in_(society_ids), _current_filter())
        .group_by(Flat.society_id)
        .all()
    )
    return {sid: (a, b) for sid, a, b in rows}


def _status(m: Meeting, now: datetime) -> str:
    if m.cancelled_at is not None:
        return "cancelled"
    return "upcoming" if m.scheduled_at >= now else "past"


def _ser(m: Meeting, counts: dict, now: datetime) -> dict:
    ev, ow = counts.get(m.society_id, (0, 0))
    return {
        "id": m.id,
        "title": m.title,
        "agenda": m.agenda,
        "location": m.location,
        "scheduled_at": m.scheduled_at.astimezone(timezone.utc).isoformat(),
        "audience": m.audience,
        "status": _status(m, now),
        "invited_count": ow if m.audience == "owners" else ev,
        "created_at": m.created_at.astimezone(timezone.utc).isoformat() if m.created_at else None,
        "cancelled_at": m.cancelled_at.astimezone(timezone.utc).isoformat() if m.cancelled_at else None,
    }


def _serialize_list(db: Session, rows: list[Meeting]) -> list[dict]:
    now = _now()
    counts = _counts(db, {m.society_id for m in rows})
    return [_ser(m, counts, now) for m in rows]


def _order(rows: list[Meeting], now: datetime) -> list[Meeting]:
    up = sorted(
        (m for m in rows if m.cancelled_at is None and m.scheduled_at >= now),
        key=lambda m: (m.scheduled_at, m.id),
    )
    rest = sorted(
        (m for m in rows if not (m.cancelled_at is None and m.scheduled_at >= now)),
        key=lambda m: (m.scheduled_at, m.id),
        reverse=True,
    )
    return up + rest


class MeetingIn(BaseModel):
    title: str = Field(max_length=150)
    agenda: str | None = Field(default=None, max_length=2000)
    location: str | None = Field(default=None, max_length=150)
    scheduled_at: datetime
    audience: Literal["everyone", "owners"] = "everyone"

    @field_validator("title")
    @classmethod
    def _title(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Please enter a title for the meeting.")
        return v

    @field_validator("scheduled_at")
    @classmethod
    def _when(cls, v: datetime) -> datetime:
        if v.tzinfo is None:
            v = v.replace(tzinfo=timezone.utc)
        now = _now()
        if v <= now:
            raise ValueError("Please pick a time in the future.")
        if v > now + timedelta(days=MAX_DAYS_AHEAD):
            raise ValueError("Please pick a time within the next year.")
        return v


def _meeting_in_society(db: Session, meeting_id: int, society_id: int) -> Meeting:
    m = db.get(Meeting, meeting_id)
    if m is None or m.society_id != society_id:
        raise HTTPException(404, "We could not find that meeting.")
    return m


def _when_text(m: Meeting) -> str:
    return m.scheduled_at.astimezone(timezone.utc).strftime("%d %b %Y, %H:%M UTC")


# --------------------------------------------------------------- secretary
@router.post("/secretary/meetings", status_code=201)
def create_meeting(
    body: MeetingIn,
    ctx: SocietyContext = Depends(require_secretary),
    db: Session = Depends(get_db),
):
    m = Meeting(
        society_id=ctx.society_id,
        title=body.title,
        agenda=(body.agenda or "").strip() or None,
        location=(body.location or "").strip() or None,
        scheduled_at=body.scheduled_at,
        audience=body.audience,
        created_by=ctx.user.id,
    )
    db.add(m)
    db.flush()
    audit(db, ctx.user, ctx.society_id, "meeting.created", "meeting", m.id,
          {"audience": m.audience})
    db.commit()
    db.refresh(m)
    notify_users(
        db,
        [u for u in _invited_ids(db, ctx.society_id, m.audience) if u != ctx.user.id],
        "New society meeting",
        f"{m.title} on {_when_text(m)}",
        {"type": "meeting_created", "meeting_id": str(m.id)},
    )
    return _serialize_list(db, [m])[0]


@router.get("/secretary/meetings")
def secretary_meetings(
    ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)
):
    now = _now()
    base = db.query(Meeting).filter(Meeting.society_id == ctx.society_id)
    up = (
        base.filter(Meeting.cancelled_at.is_(None), Meeting.scheduled_at >= now)
        .order_by(Meeting.scheduled_at, Meeting.id)
        .limit(LIMIT)
        .all()
    )
    rest = (
        base.filter(or_(Meeting.cancelled_at.is_not(None), Meeting.scheduled_at < now))
        .order_by(Meeting.scheduled_at.desc(), Meeting.id.desc())
        .limit(max(LIMIT - len(up), 0))
        .all()
    )
    return _serialize_list(db, up + rest)


@router.post("/secretary/meetings/{meeting_id}/cancel")
def cancel_meeting(
    meeting_id: int,
    ctx: SocietyContext = Depends(require_secretary),
    db: Session = Depends(get_db),
):
    m = _meeting_in_society(db, meeting_id, ctx.society_id)
    if m.cancelled_at is None:
        m.cancelled_at = _now()
        audit(db, ctx.user, ctx.society_id, "meeting.cancelled", "meeting", m.id)
        db.commit()
        db.refresh(m)
        notify_users(
            db,
            [u for u in _invited_ids(db, ctx.society_id, m.audience) if u != ctx.user.id],
            "Society meeting cancelled",
            f"{m.title} on {_when_text(m)} has been cancelled.",
            {"type": "meeting_cancelled", "meeting_id": str(m.id)},
        )
    return _serialize_list(db, [m])[0]


# ---------------------------------------------------------------- residents
@router.get("/meetings")
def my_meetings(user: User = Depends(current_user), db: Session = Depends(get_db)):
    ms = current_flat_memberships(db, user.id)
    if not ms:
        return []
    owner_societies: set[int] = set()
    all_societies: set[int] = set()
    for m in ms:
        all_societies.add(m.flat.society_id)
        if m.kind == "owner":
            owner_societies.add(m.flat.society_id)

    now = _now()
    cutoff = now - timedelta(days=RECENT_DAYS)
    audience_ok = Meeting.audience == "everyone"
    if owner_societies:
        audience_ok = or_(audience_ok, Meeting.society_id.in_(owner_societies))
    rows = (
        db.query(Meeting)
        .filter(
            Meeting.society_id.in_(all_societies),
            audience_ok,
            or_(
                and_(Meeting.cancelled_at.is_(None), Meeting.scheduled_at >= now),
                and_(
                    Meeting.scheduled_at >= cutoff,
                    or_(Meeting.cancelled_at.is_not(None), Meeting.scheduled_at < now),
                ),
            ),
        )
        .limit(LIMIT * 2)
        .all()
    )
    return _serialize_list(db, _order(rows, now)[:LIMIT])
