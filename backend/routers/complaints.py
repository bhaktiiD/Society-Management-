"""Complaints: residents raise them, the society admin moves them open ->
in_progress -> resolved. A resident only ever sees their own."""
from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.orm import Session

from deps import (
    SocietyContext,
    audit,
    current_user,
    get_db,
    require_secretary,
    user_flat_ids,
)
from models import Complaint, Flat, SocietyAdminMembership, User
from push import notify_users

router = APIRouter(tags=["complaints"])

Category = Literal[
    "plumbing", "electrical", "lift", "security", "cleaning", "parking", "noise", "other"
]
Status = Literal["open", "in_progress", "resolved"]


def _iso(d: datetime | None) -> str | None:
    return d.isoformat() if d else None


def _ser(c: Complaint, flat_number: str | None = None) -> dict:
    return {
        "id": c.id,
        "category": c.category,
        "title": c.title,
        "description": c.description,
        "status": c.status,
        "admin_note": c.admin_note,
        "flat_number": flat_number,
        "created_at": _iso(c.created_at),
        "updated_at": _iso(c.updated_at),
        "resolved_at": _iso(c.resolved_at),
    }


class ComplaintIn(BaseModel):
    category: Category
    title: str = Field(min_length=1, max_length=120)
    description: str = Field(min_length=1, max_length=2000)
    flat_id: int | None = None

    @field_validator("title", "description")
    @classmethod
    def _not_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v


@router.post("/complaints", status_code=201)
def create_complaint(
    body: ComplaintIn, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    flat_ids = user_flat_ids(db, user.id)
    if not flat_ids:
        raise HTTPException(403, "Only residents can raise complaints.")
    flat_id = body.flat_id if body.flat_id is not None else flat_ids[0]
    if flat_id not in flat_ids:
        raise HTTPException(404, "Flat not found")
    flat = db.get(Flat, flat_id)

    c = Complaint(
        society_id=flat.society_id,
        flat_id=flat.id,
        created_by=user.id,
        category=body.category,
        title=body.title,
        description=body.description,
        status="open",
    )
    db.add(c)
    db.flush()
    audit(db, user, flat.society_id, "complaint.created", "complaint", c.id,
          {"category": c.category})
    db.commit()
    db.refresh(c)

    admins = [
        r[0]
        for r in db.query(SocietyAdminMembership.user_id)
        .filter(
            SocietyAdminMembership.society_id == flat.society_id,
            SocietyAdminMembership.revoked_at.is_(None),
        )
        .all()
    ]
    if admins:
        notify_users(
            db, admins, "New complaint",
            f"Flat {flat.flat_number}: {c.title}",
            {"type": "complaint_created", "complaint_id": c.id},
        )
    return _ser(c, flat.flat_number)


@router.get("/complaints")
def my_complaints(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = (
        db.query(Complaint, Flat.flat_number)
        .outerjoin(Flat, Flat.id == Complaint.flat_id)
        .filter(Complaint.created_by == user.id)
        .order_by(Complaint.created_at.desc(), Complaint.id.desc())
        .all()
    )
    return [_ser(c, fn) for c, fn in rows]


@router.get("/secretary/complaints")
def admin_list(
    status: Status | None = None,
    ctx: SocietyContext = Depends(require_secretary),
    db: Session = Depends(get_db),
):
    q = (
        db.query(Complaint, Flat.flat_number, User.full_name, User.email)
        .outerjoin(Flat, Flat.id == Complaint.flat_id)
        .join(User, User.id == Complaint.created_by)
        .filter(Complaint.society_id == ctx.society_id)
    )
    if status:
        q = q.filter(Complaint.status == status)
    rows = q.order_by(Complaint.created_at.desc(), Complaint.id.desc()).all()
    return [
        {**_ser(c, fn), "created_by_name": name, "created_by_email": email}
        for c, fn, name, email in rows
    ]


class ComplaintUpdate(BaseModel):
    status: Status
    admin_note: str | None = Field(default=None, max_length=1000)


@router.patch("/secretary/complaints/{complaint_id}")
def admin_update(
    complaint_id: int,
    body: ComplaintUpdate,
    ctx: SocietyContext = Depends(require_secretary),
    db: Session = Depends(get_db),
):
    c = db.get(Complaint, complaint_id)
    if c is None or c.society_id != ctx.society_id:
        raise HTTPException(404, "We could not find that complaint.")

    now = datetime.now(timezone.utc)
    c.status = body.status
    c.resolved_at = now if body.status == "resolved" else None
    if body.admin_note is not None:
        c.admin_note = body.admin_note.strip() or None
    c.updated_at = now
    audit(db, ctx.user, ctx.society_id, "complaint.updated", "complaint", c.id,
          {"status": c.status})
    db.commit()
    db.refresh(c)

    notify_users(
        db, [c.created_by], "Your complaint was updated",
        f"{c.title}: {c.status.replace('_', ' ')}",
        {"type": "complaint_updated", "complaint_id": c.id},
    )
    flat = db.get(Flat, c.flat_id) if c.flat_id else None
    return _ser(c, flat.flat_number if flat else None)
