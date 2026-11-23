"""Society polls: the admin asks, residents vote once.

One vote per person is enforced by the unique constraint uq_poll_vote_user; the
insert is the source of truth (IntegrityError -> 409), the pre-check is UX only.
Results stay hidden from a resident until they have voted or the poll is closed.
"""
from datetime import date, datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func, or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from deps import (
    SocietyContext,
    audit,
    current_flat_memberships,
    current_user,
    get_db,
    require_secretary,
    secretary_society_ids,
)
from models import Flat, FlatMembership, Poll, PollOption, PollVote, User
from push import notify_users

router = APIRouter(tags=["polls"])

MAX_DAYS_AHEAD = 90
CLOSED_VISIBLE_DAYS = 60


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _aware(dt: datetime) -> datetime:
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def _is_closed(p: Poll, now: datetime) -> bool:
    return p.closed_at is not None or _aware(p.closes_at) <= now


def _iso(dt):
    return _aware(dt).isoformat() if dt else None


def _current_members(society_id: int):
    today = date.today()
    return (
        FlatMembership.start_date <= today,
        or_(FlatMembership.end_date.is_(None), FlatMembership.end_date >= today),
        Flat.society_id == society_id,
    )


def _eligible_counts(db: Session, society_ids) -> dict[int, tuple[int, int]]:
    """society_id -> (owners, everyone), distinct people with a current membership."""
    today = date.today()
    rows = (
        db.query(
            Flat.society_id,
            func.count(func.distinct(FlatMembership.user_id)).filter(FlatMembership.kind == "owner"),
            func.count(func.distinct(FlatMembership.user_id)),
        )
        .join(Flat, Flat.id == FlatMembership.flat_id)
        .filter(
            Flat.society_id.in_(list(society_ids)),
            FlatMembership.start_date <= today,
            or_(FlatMembership.end_date.is_(None), FlatMembership.end_date >= today),
        )
        .group_by(Flat.society_id)
        .all()
    )
    out = {sid: (0, 0) for sid in society_ids}
    for sid, owners, everyone in rows:
        out[sid] = (owners, everyone)
    return out


def _can_vote_kinds(audience: str) -> set[str]:
    return {"owner"} if audience == "owners" else {"owner", "tenant"}


def _serialize(db: Session, polls: list[Poll], viewer: User | None, memberships=None) -> list[dict]:
    """Serialize many polls with a fixed number of queries. viewer None = admin view."""
    if not polls:
        return []
    now = _now()
    ids = [p.id for p in polls]
    options = (
        db.query(PollOption)
        .filter(PollOption.poll_id.in_(ids))
        .order_by(PollOption.poll_id, PollOption.position, PollOption.id)
        .all()
    )
    by_poll: dict[int, list[PollOption]] = {}
    for o in options:
        by_poll.setdefault(o.poll_id, []).append(o)
    counts = dict(
        db.query(PollVote.option_id, func.count(PollVote.id))
        .filter(PollVote.poll_id.in_(ids))
        .group_by(PollVote.option_id)
        .all()
    )
    mine: dict[int, int] = {}
    if viewer is not None:
        mine = dict(
            db.query(PollVote.poll_id, PollVote.option_id)
            .filter(PollVote.poll_id.in_(ids), PollVote.user_id == viewer.id)
            .all()
        )
    elig = _eligible_counts(db, {p.society_id for p in polls})
    kinds_by_society: dict[int, set[str]] = {}
    for m in memberships or []:
        kinds_by_society.setdefault(m.flat.society_id, set()).add(m.kind)

    out = []
    for p in polls:
        closed = _is_closed(p, now)
        admin = viewer is None
        voted = p.id in mine
        eligible = (not admin) and bool(
            kinds_by_society.get(p.society_id, set()) & _can_vote_kinds(p.audience)
        )
        show = admin or voted or closed
        opts = by_poll.get(p.id, [])
        total = sum(counts.get(o.id, 0) for o in opts)
        owners, everyone = elig[p.society_id]
        out.append(
            {
                "id": p.id,
                "title": p.title,
                "description": p.description,
                "audience": p.audience,
                "status": "closed" if closed else "open",
                "created_at": _iso(p.created_at),
                "closes_at": _iso(p.closes_at),
                "closed_at": _iso(p.closed_at),
                "eligible": eligible,
                "can_vote": eligible and not closed and not voted,
                "has_voted": voted,
                "my_option_id": mine.get(p.id),
                "total_votes": total,
                "eligible_count": owners if p.audience == "owners" else everyone,
                "options": [
                    {"id": o.id, "text": o.text, "votes": counts.get(o.id, 0) if show else None}
                    for o in opts
                ],
            }
        )
    return out


# ---------------------------------------------------------------- residents
@router.get("/polls")
def list_polls(user: User = Depends(current_user), db: Session = Depends(get_db)):
    memberships = current_flat_memberships(db, user.id)
    if memberships:
        sid = memberships[0].flat.society_id
    else:
        ids = secretary_society_ids(db, user.id)
        if not ids:
            return []
        sid = ids[0]
    return _list_for_society(db, sid, user, memberships)


def _list_for_society(db: Session, sid: int, viewer: User | None, memberships=None) -> list[dict]:
    now = _now()
    cutoff = now - timedelta(days=CLOSED_VISIBLE_DAYS)
    rows = db.query(Poll).filter(Poll.society_id == sid).all()
    open_, closed = [], []
    for p in rows:
        if _is_closed(p, now):
            end = min(
                _aware(p.closes_at), _aware(p.closed_at) if p.closed_at else _aware(p.closes_at)
            )
            if end >= cutoff:
                closed.append((end, p))
        else:
            open_.append(p)
    open_.sort(key=lambda p: (_aware(p.closes_at), p.id))
    closed.sort(key=lambda t: (t[0], t[1].id), reverse=True)
    return _serialize(db, open_ + [p for _, p in closed], viewer, memberships)


class VoteIn(BaseModel):
    option_id: int


@router.post("/polls/{poll_id}/vote")
def vote(
    poll_id: int,
    body: VoteIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    memberships = current_flat_memberships(db, user.id)
    if not memberships:
        raise HTTPException(403, "Only residents of this society can vote.")
    poll = db.get(Poll, poll_id)
    if poll is None or not any(m.flat.society_id == poll.society_id for m in memberships):
        raise HTTPException(404, "We could not find that poll.")
    kinds = {m.kind for m in memberships if m.flat.society_id == poll.society_id}
    if not kinds & _can_vote_kinds(poll.audience):
        raise HTTPException(
            403,
            "Only owners can vote in this poll."
            if poll.audience == "owners"
            else "Only residents of this society can vote.",
        )
    if _is_closed(poll, _now()):
        raise HTTPException(409, "This poll has closed.")
    option_ids = {
        r[0] for r in db.query(PollOption.id).filter(PollOption.poll_id == poll.id).all()
    }
    if body.option_id not in option_ids:
        raise HTTPException(422, "Please pick one of the options in this poll.")
    already = "You have already voted in this poll."
    if (
        db.query(PollVote.id)
        .filter(PollVote.poll_id == poll.id, PollVote.user_id == user.id)
        .first()
    ):
        raise HTTPException(409, already)
    db.add(PollVote(poll_id=poll.id, option_id=body.option_id, user_id=user.id))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, already)
    return _serialize(db, [poll], user, memberships)[0]


# ---------------------------------------------------------------- secretary
class PollIn(BaseModel):
    title: str
    description: str | None = Field(default=None, max_length=1000)
    audience: Literal["everyone", "owners"] = "everyone"
    options: list[str] = Field(min_length=2, max_length=6)
    closes_at: datetime

    @field_validator("title")
    @classmethod
    def _title(cls, v: str) -> str:
        v = v.strip()
        if not v or len(v) > 150:
            raise ValueError("Please enter a title of up to 150 characters.")
        return v

    @field_validator("description")
    @classmethod
    def _desc(cls, v):
        return (v or "").strip() or None

    @field_validator("options")
    @classmethod
    def _options(cls, v: list[str]) -> list[str]:
        out = [o.strip() for o in v]
        if any(not o or len(o) > 120 for o in out):
            raise ValueError("Each option must be 1 to 120 characters.")
        if len({o.lower() for o in out}) != len(out):
            raise ValueError("Each option must be different.")
        return out


@router.post("/secretary/polls", status_code=201)
def create_poll(
    body: PollIn, ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)
):
    closes = _aware(body.closes_at)
    now = _now()
    if closes <= now:
        raise HTTPException(422, "The closing time must be in the future.")
    if closes > now + timedelta(days=MAX_DAYS_AHEAD):
        raise HTTPException(422, f"A poll can stay open for at most {MAX_DAYS_AHEAD} days.")
    poll = Poll(
        society_id=ctx.society_id,
        title=body.title,
        description=body.description,
        audience=body.audience,
        created_by=ctx.user.id,
        closes_at=closes,
    )
    db.add(poll)
    db.flush()
    db.add_all(PollOption(poll_id=poll.id, text=t, position=i) for i, t in enumerate(body.options))
    audit(
        db, ctx.user, ctx.society_id, "poll.created", "poll", poll.id,
        {"title": poll.title, "audience": poll.audience},
    )
    db.commit()
    db.refresh(poll)

    q = (
        db.query(FlatMembership.user_id)
        .join(Flat, Flat.id == FlatMembership.flat_id)
        .filter(*_current_members(ctx.society_id))
    )
    if poll.audience == "owners":
        q = q.filter(FlatMembership.kind == "owner")
    user_ids = {r[0] for r in q.distinct().all()}
    notify_users(db, user_ids, "New poll", poll.title, {"type": "poll_created", "poll_id": str(poll.id)})
    return _serialize(db, [poll], None)[0]


@router.get("/secretary/polls")
def secretary_polls(ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)):
    return _list_for_society(db, ctx.society_id, None)


@router.post("/secretary/polls/{poll_id}/close")
def close_poll(
    poll_id: int, ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)
):
    poll = db.get(Poll, poll_id)
    if poll is None or poll.society_id != ctx.society_id:
        raise HTTPException(404, "We could not find that poll.")
    if poll.closed_at is None:
        poll.closed_at = _now()
        audit(db, ctx.user, ctx.society_id, "poll.closed", "poll", poll.id)
        db.commit()
        db.refresh(poll)
    return _serialize(db, [poll], None)[0]
