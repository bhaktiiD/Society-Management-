from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import case
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
from models import SocietyContact, User

router = APIRouter(tags=["contacts"])

CATEGORY_RANK = case(
    (SocietyContact.category == "emergency", 0),
    (SocietyContact.category == "staff", 1),
    else_=2,
)


class ContactIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    label: str | None = Field(default=None, max_length=60)
    phone: str = Field(pattern=r"^[0-9+() \-]{3,20}$")
    category: str = Field(default="service", pattern="^(emergency|staff|service)$")
    sort_order: int = Field(default=0, ge=0, le=1000)


def _out(c: SocietyContact) -> dict:
    return {
        "id": c.id,
        "name": c.name,
        "label": c.label,
        "phone": c.phone,
        "category": c.category,
        "sort_order": c.sort_order,
    }


def _apply(c: SocietyContact, body: ContactIn) -> None:
    name = " ".join(body.name.split())
    phone = body.phone.strip()
    if not name:
        raise HTTPException(422, "Name cannot be empty")
    if len(phone) < 3:
        raise HTTPException(422, "Please enter a valid phone number.")
    c.name = name
    c.label = " ".join(body.label.split()) if body.label and body.label.strip() else None
    c.phone = phone
    c.category = body.category
    c.sort_order = body.sort_order


@router.get("/contacts")
def list_contacts(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Contacts of every society I currently belong to (any role)."""
    ids = set(secretary_society_ids(db, user.id)) | set(guard_society_ids(db, user.id))
    ids |= {m.flat.society_id for m in current_flat_memberships(db, user.id)}
    if not ids:
        return []
    rows = (
        db.query(SocietyContact)
        .filter(SocietyContact.society_id.in_(ids))
        .order_by(CATEGORY_RANK, SocietyContact.sort_order, SocietyContact.name)
        .all()
    )
    return [_out(c) for c in rows]


@router.post("/secretary/contacts", status_code=201)
def create_contact(
    body: ContactIn, ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)
):
    c = SocietyContact(society_id=ctx.society_id)
    _apply(c, body)
    db.add(c)
    db.flush()
    audit(db, ctx.user, ctx.society_id, "contact.created", "contact", c.id, {"name": c.name})
    db.commit()
    return _out(c)


def _own(db: Session, ctx: SocietyContext, contact_id: int) -> SocietyContact:
    c = db.get(SocietyContact, contact_id)
    if c is None or c.society_id != ctx.society_id:
        raise HTTPException(404, "We could not find that contact.")
    return c


@router.put("/secretary/contacts/{contact_id}")
def update_contact(
    contact_id: int,
    body: ContactIn,
    ctx: SocietyContext = Depends(require_secretary),
    db: Session = Depends(get_db),
):
    c = _own(db, ctx, contact_id)
    _apply(c, body)
    audit(db, ctx.user, ctx.society_id, "contact.updated", "contact", c.id, {"name": c.name})
    db.commit()
    return _out(c)


@router.delete("/secretary/contacts/{contact_id}", status_code=204)
def delete_contact(
    contact_id: int, ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)
):
    c = _own(db, ctx, contact_id)
    audit(db, ctx.user, ctx.society_id, "contact.deleted", "contact", c.id, {"name": c.name})
    db.delete(c)
    db.commit()
