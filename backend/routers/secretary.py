from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from billing_service import FLAT_TYPES, ensure_billing
from deps import (
    SocietyContext,
    audit,
    current_flat_memberships,  # noqa: F401  (re-exported for tests)
    get_db,
    pick_responsible,
    require_secretary,
)
from models import (
    Charge,
    Flat,
    FlatMembership,
    Invite,
    Notice,
    PaymentAllocation,
    Society,
    User,
)
from push import notify_users
from sqlalchemy import or_

router = APIRouter(prefix="/secretary", tags=["secretary"])


# ---------------------------------------------------------------- flats
class SocietyIn(BaseModel):
    name: str = Field(min_length=1, max_length=150)


@router.get("/society")
def get_society(ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)):
    society = db.get(Society, ctx.society_id)
    return {"id": society.id, "name": society.name}


@router.patch("/society")
def rename_society(
    body: SocietyIn, ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)
):
    name = " ".join(body.name.split())
    if not name:
        raise HTTPException(422, "Please enter a name.")
    society = db.get(Society, ctx.society_id)
    society.name = name
    audit(db, ctx.user, ctx.society_id, "society.renamed", "society", society.id, {"name": name})
    db.commit()
    return {"id": society.id, "name": society.name}


FLAT_TYPE_PATTERN ="^(" + "|".join(FLAT_TYPES) + ")$"


class FlatIn(BaseModel):
    flat_number: str = Field(min_length=1, max_length=20)
    flat_type: str | None = Field(default=None, pattern=FLAT_TYPE_PATTERN)


class FlatTypeIn(BaseModel):
    flat_type: str = Field(pattern=FLAT_TYPE_PATTERN)


@router.put("/flats/{flat_id}/type")
def set_flat_type(
    flat_id: int,
    body: FlatTypeIn,
    ctx: SocietyContext = Depends(require_secretary),
    db: Session = Depends(get_db),
):
    flat = db.get(Flat, flat_id)
    if flat is None or flat.society_id != ctx.society_id:
        raise HTTPException(404, "We could not find that flat.")
    flat.flat_type = body.flat_type
    audit(db, ctx.user, ctx.society_id, "flat.type_set", "flat", flat.id, {"type": body.flat_type})
    db.commit()
    ensure_billing(db, ctx.society_id, force=True)  # a newly typed flat gets this month's bill
    return {"id": flat.id, "flat_type": flat.flat_type}


@router.post("/flats", status_code=201)
def create_flat(
    body: FlatIn, ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)
):
    flat = Flat(
        society_id=ctx.society_id, flat_number=body.flat_number.strip(), flat_type=body.flat_type
    )
    db.add(flat)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "A flat with this number already exists.")
    audit(db, ctx.user, ctx.society_id, "flat.created", "flat", flat.id)
    db.commit()
    return {"id": flat.id, "flat_number": flat.flat_number}


@router.get("/flats")
def list_flats(ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)):
    today = date.today()
    flats = db.query(Flat).filter(Flat.society_id == ctx.society_id).order_by(Flat.flat_number).all()
    invites_by_flat: dict[int, list[Invite]] = {}
    for inv in db.query(Invite).filter(
        Invite.society_id == ctx.society_id,
        Invite.accepted_at.is_(None),
        Invite.flat_id.isnot(None),
    ):
        invites_by_flat.setdefault(inv.flat_id, []).append(inv)
    out = []
    for f in flats:
        members = [
            {
                "membership_id": m.id,
                "user_id": str(m.user_id),
                "name": m.user.full_name,
                "email": m.user.email,
                "phone": m.user.phone,
                "kind": m.kind,
                "is_resident": m.is_resident,
            }
            for m in f.memberships
            if m.start_date <= today and (m.end_date is None or m.end_date >= today)
        ]
        pending = [
            {"id": i.id, "email": i.email, "role": i.role, "full_name": i.full_name, "phone": i.phone}
            for i in invites_by_flat.get(f.id, [])
        ]
        out.append(
            {
                "id": f.id,
                "flat_number": f.flat_number,
                "flat_type": f.flat_type,
                "members": members,
                "pending_invites": pending,
            }
        )
    return out


@router.post("/memberships/{membership_id}/end", status_code=204)
def end_membership(
    membership_id: int,
    ctx: SocietyContext = Depends(require_secretary),
    db: Session = Depends(get_db),
):
    """Move-out / ownership change. History is kept: the row gets an end date.
    Charges already raised stay with the person they were snapshotted to."""
    m = db.get(FlatMembership, membership_id)
    flat = db.get(Flat, m.flat_id) if m else None
    if m is None or flat is None or flat.society_id != ctx.society_id:
        raise HTTPException(404, "We could not find that person in this flat.")
    yesterday = date.today() - timedelta(days=1)
    if m.end_date is None or m.end_date > yesterday:
        # end_date is inclusive, so "yesterday" makes the change immediate.
        m.end_date = yesterday
        m.start_date = min(m.start_date, yesterday)  # keep end >= start
        audit(db, ctx.user, ctx.society_id, "membership.ended", "flat_membership", m.id)
        db.commit()


@router.delete("/invites/{invite_id}", status_code=204)
def revoke_invite(
    invite_id: int, ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)
):
    inv = db.get(Invite, invite_id)
    if inv is None or inv.society_id != ctx.society_id or inv.accepted_at is not None:
        raise HTTPException(404, "We could not find that registration.")
    audit(db, ctx.user, ctx.society_id, "invite.revoked", "invite", inv.id)
    db.delete(inv)
    db.commit()


# -------------------------------------------------------------- invites
class InviteIn(BaseModel):
    email: str = Field(min_length=3, max_length=150)
    role: str = Field(pattern="^(owner|tenant|secretary|guard)$")
    flat_id: int | None = None
    is_resident: bool = True
    full_name: str | None = Field(default=None, max_length=100)
    phone: str | None = Field(default=None, pattern=r"^[0-9+() \-]{3,20}$")


@router.post("/invites", status_code=201)
def create_invite(
    body: InviteIn, ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)
):
    if body.role in ("owner", "tenant"):
        if body.flat_id is None:
            raise HTTPException(422, "Please choose a flat for this person.")
        flat = db.get(Flat, body.flat_id)
        if flat is None or flat.society_id != ctx.society_id:
            raise HTTPException(404, "We could not find that flat.")  # never reveal other societies
    else:
        body.flat_id = None
    is_resident = body.is_resident if body.role in ("owner", "tenant") else False
    if body.role == "tenant":
        is_resident = True  # a tenant is by definition the occupant
    email = body.email.strip().lower()
    already = (
        db.query(Invite.id)
        .filter(
            Invite.society_id == ctx.society_id,
            Invite.email == email,
            Invite.role == body.role,
            Invite.flat_id.is_(body.flat_id) if body.flat_id is None else Invite.flat_id == body.flat_id,
            Invite.accepted_at.is_(None),
        )
        .first()
    )
    if already:
        raise HTTPException(409, "This email is already registered here and waiting to sign up.")
    inv = Invite(
        society_id=ctx.society_id,
        email=email,
        role=body.role,
        flat_id=body.flat_id,
        is_resident=is_resident,
        full_name=" ".join(body.full_name.split()) if body.full_name and body.full_name.strip() else None,
        phone=body.phone.strip() if body.phone else None,
        invited_by=ctx.user.id,
    )
    db.add(inv)
    db.flush()
    audit(db, ctx.user, ctx.society_id, "invite.created", "invite", inv.id, {"role": body.role})
    db.commit()
    return {"id": inv.id, "email": inv.email, "role": inv.role}


@router.get("/invites")
def list_invites(ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)):
    rows = (
        db.query(Invite)
        .filter(Invite.society_id == ctx.society_id)
        .order_by(Invite.created_at.desc())
        .limit(100)
        .all()
    )
    return [
        {
            "id": i.id,
            "email": i.email,
            "role": i.role,
            "flat_id": i.flat_id,
            "accepted": i.accepted_at is not None,
        }
        for i in rows
        if i.flat_id is None  # flat invites are shown under their flat
    ]


# -------------------------------------------------------------- charges
class ChargeIn(BaseModel):
    # None = bill EVERY flat in the society (society-wide festival / repair charge).
    flat_id: int | None = None
    charge_type: str = Field(pattern="^(maintenance|festival|repair)$")
    title: str = Field(min_length=1, max_length=150)
    amount_paise: int = Field(gt=0, le=100_000_000)  # integer paise, max 10 lakh INR
    due_date: date
    # Maintenance is always owner-paid. Festival/repair may be assigned.
    responsible: str = Field(default="owner", pattern="^(owner|tenant)$")


def _charge_all_flats(body: ChargeIn, ctx: SocietyContext, db: Session) -> dict:
    """Society-wide festival / repair charge: one bill per flat, all or nothing.

    Responsible person per flat: the owner or tenant the admin picked. If a flat
    has no tenant, the owner is billed instead. Flats with nobody registered are
    skipped and reported back so the admin can follow up.
    """
    if body.charge_type == "maintenance":
        raise HTTPException(422, "Monthly maintenance is billed automatically (Maintenance settings)")
    title = body.title.strip()

    # Guard against double-tapping / resubmitting the same society-wide charge.
    duplicate = (
        db.query(Charge.id)
        .filter(
            Charge.society_id == ctx.society_id,
            Charge.charge_type == body.charge_type,
            Charge.title == title,
            Charge.due_date == body.due_date,
            Charge.period.is_(None),
        )
        .first()
    )
    if duplicate:
        raise HTTPException(409, "A charge with this title and due date already exists")

    flats = db.query(Flat).filter(Flat.society_id == ctx.society_id).order_by(Flat.id).all()
    if not flats:
        raise HTTPException(422, "Add at least one flat first.")

    billed_users, skipped, billed_owner_instead = [], [], 0
    for flat in flats:
        member = pick_responsible(db, flat.id, body.responsible)
        if member is None and body.responsible == "tenant":
            member = pick_responsible(db, flat.id, "owner")
            if member is not None:
                billed_owner_instead += 1
        if member is None:
            skipped.append(flat.flat_number)
            continue
        db.add(
            Charge(
                society_id=ctx.society_id,
                flat_id=flat.id,
                charge_type=body.charge_type,
                title=title,
                amount_paise=body.amount_paise,
                due_date=body.due_date,
                responsible_user_id=member.user_id,
                created_by=ctx.user.id,
            )
        )
        billed_users.append(member.user_id)

    if not billed_users:
        raise HTTPException(422, "No flat has a registered owner or tenant to bill yet.")

    audit(
        db, ctx.user, ctx.society_id, "charge.broadcast", "society", ctx.society_id,
        {"type": body.charge_type, "title": title, "amount_paise": body.amount_paise,
         "flats_billed": len(billed_users), "flats_skipped": len(skipped)},
    )
    db.commit()
    notify_users(
        db, billed_users, "New charge",
        f"{title}: ₹{body.amount_paise / 100:.2f} due {body.due_date}",
        {"type": "charge"},
    )
    return {
        "created": len(billed_users),
        "skipped_flats": skipped,
        "billed_owner_instead": billed_owner_instead,
    }


@router.post("/charges", status_code=201)
def create_charge(
    body: ChargeIn, ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)
):
    if body.flat_id is None:
        return _charge_all_flats(body, ctx, db)

    flat = db.get(Flat, body.flat_id)
    if flat is None or flat.society_id != ctx.society_id:
        raise HTTPException(404, "We could not find that flat.")

    kind = "owner" if body.charge_type == "maintenance" else body.responsible
    member = pick_responsible(db, body.flat_id, kind)
    if member is None:
        raise HTTPException(422, f"This flat has no {kind} registered to bill yet.")

    # Snapshot: responsible_user_id is fixed now and never follows later moves.
    charge = Charge(
        society_id=ctx.society_id,
        flat_id=body.flat_id,
        charge_type=body.charge_type,
        title=body.title.strip(),
        amount_paise=body.amount_paise,
        due_date=body.due_date,
        responsible_user_id=member.user_id,
        created_by=ctx.user.id,
    )
    db.add(charge)
    db.flush()
    audit(
        db, ctx.user, ctx.society_id, "charge.created", "charge", charge.id,
        {"amount_paise": charge.amount_paise, "responsible": str(member.user_id)},
    )
    db.commit()
    notify_users(
        db, [member.user_id], "New charge",
        f"{charge.title}: ₹{charge.amount_paise / 100:.2f} due {charge.due_date}",
        {"type": "charge", "charge_id": charge.id},
    )
    return {"id": charge.id, "responsible_user_id": str(member.user_id)}


def _paid_map(db: Session, charge_ids) -> dict[int, int]:
    if not charge_ids:
        return {}
    rows = (
        db.query(PaymentAllocation.charge_id, func.sum(PaymentAllocation.amount_paise))
        .filter(PaymentAllocation.charge_id.in_(charge_ids))
        .group_by(PaymentAllocation.charge_id)
        .all()
    )
    return {cid: int(total) for cid, total in rows}


def serialize_charge(c: Charge, paid: int) -> dict:
    balance = c.amount_paise - paid
    return {
        "id": c.id,
        "flat_id": c.flat_id,
        "charge_type": c.charge_type,
        "title": c.title,
        "amount_paise": c.amount_paise,
        "paid_paise": paid,
        "balance_paise": balance,
        "status": "paid" if balance <= 0 else ("partial" if paid > 0 else "outstanding"),
        "due_date": c.due_date.isoformat(),
        "overdue": balance > 0 and c.due_date < date.today(),
    }


@router.get("/charges")
def list_charges(ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)):
    ensure_billing(db, ctx.society_id)
    charges = (
        db.query(Charge)
        .filter(Charge.society_id == ctx.society_id)
        .order_by(Charge.due_date.desc(), Charge.id.desc())
        .limit(200)
        .all()
    )
    paid = _paid_map(db, [c.id for c in charges])
    flats = {f.id: f.flat_number for f in db.query(Flat).filter(Flat.society_id == ctx.society_id)}
    out = []
    for c in charges:
        row = serialize_charge(c, paid.get(c.id, 0))
        row["flat_number"] = flats.get(c.flat_id)
        out.append(row)
    return out


@router.get("/collections")
def collections(ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)):
    """Dashboard totals, derived from allocations (never stored)."""
    ensure_billing(db, ctx.society_id)
    charges = db.query(Charge).filter(Charge.society_id == ctx.society_id).all()
    paid = _paid_map(db, [c.id for c in charges])
    billed = sum(c.amount_paise for c in charges)
    collected = sum(min(paid.get(c.id, 0), c.amount_paise) for c in charges)
    # The home card says "Maintenance collected": monthly bills + their late fees only.
    maint = [c for c in charges if c.charge_type in ("maintenance", "late_fee")]
    m_billed = sum(c.amount_paise for c in maint)
    m_collected = sum(min(paid.get(c.id, 0), c.amount_paise) for c in maint)
    counts = {"paid": 0, "partial": 0, "outstanding": 0}
    defaulters = {}
    for c in charges:
        p = paid.get(c.id, 0)
        bal = c.amount_paise - p
        counts["paid" if bal <= 0 else ("partial" if p > 0 else "outstanding")] += 1
        if bal > 0 and c.due_date < date.today():
            defaulters[c.flat_id] = defaulters.get(c.flat_id, 0) + bal
    flats = {f.id: f.flat_number for f in db.query(Flat).filter(Flat.society_id == ctx.society_id)}
    today = date.today()
    # Name the owner of each overdue flat (oldest current owner), one query.
    owner_names: dict[int, str] = {}
    if defaulters:
        for fid, name in (
            db.query(FlatMembership.flat_id, User.full_name)
            .join(User, User.id == FlatMembership.user_id)
            .filter(
                FlatMembership.flat_id.in_(list(defaulters)),
                FlatMembership.kind == "owner",
                FlatMembership.start_date <= today,
                or_(FlatMembership.end_date.is_(None), FlatMembership.end_date >= today),
            )
            .order_by(FlatMembership.start_date, FlatMembership.id)
            .all()
        ):
            owner_names.setdefault(fid, name)
    members = (
        db.query(func.count(func.distinct(FlatMembership.user_id)))
        .filter(
            FlatMembership.flat_id.in_(list(flats)) if flats else False,
            FlatMembership.start_date <= today,
            or_(FlatMembership.end_date.is_(None), FlatMembership.end_date >= today),
        )
        .scalar()
        or 0
    )
    pending_invites = (
        db.query(func.count(Invite.id))
        .filter(Invite.society_id == ctx.society_id, Invite.accepted_at.is_(None))
        .scalar()
    )
    return {
        "flat_count": len(flats),
        "member_count": members,
        "pending_invites": pending_invites,
        "billed_paise": billed,
        "collected_paise": collected,
        "outstanding_paise": billed - collected,
        "maintenance": {
            "billed_paise": m_billed,
            "collected_paise": m_collected,
            "outstanding_paise": m_billed - m_collected,
        },
        "counts": counts,
        "defaulters": [
            {
                "flat_id": fid,
                "flat_number": flats.get(fid),
                "owner_name": owner_names.get(fid),
                "overdue_paise": amt,
            }
            for fid, amt in sorted(defaulters.items(), key=lambda kv: -kv[1])
        ],
    }


# -------------------------------------------------------------- notices
class NoticeIn(BaseModel):
    title: str = Field(min_length=1, max_length=150)
    body: str = Field(min_length=1, max_length=4000)
    pinned: bool = False


@router.post("/notices", status_code=201)
def create_notice(
    body: NoticeIn, ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)
):
    notice = Notice(
        society_id=ctx.society_id,
        title=body.title.strip(),
        body=body.body.strip(),
        pinned=body.pinned,
        created_by=ctx.user.id,
    )
    db.add(notice)
    db.flush()
    audit(db, ctx.user, ctx.society_id, "notice.created", "notice", notice.id)
    db.commit()

    # Push to everyone currently attached to this society.
    today = date.today()
    ids = {
        r[0]
        for r in db.query(FlatMembership.user_id)
        .join(Flat, Flat.id == FlatMembership.flat_id)
        .filter(
            Flat.society_id == ctx.society_id,
            FlatMembership.start_date <= today,
            or_(FlatMembership.end_date.is_(None), FlatMembership.end_date >= today),
        )
        .all()
    }
    notify_users(db, ids, notice.title, notice.body[:120], {"type": "notice", "notice_id": notice.id})
    return {"id": notice.id}


@router.delete("/notices/{notice_id}", status_code=204)
def delete_notice(
    notice_id: int, ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)
):
    notice = db.get(Notice, notice_id)
    if notice is None or notice.society_id != ctx.society_id:
        raise HTTPException(404, "We could not find that notice.")
    audit(db, ctx.user, ctx.society_id, "notice.deleted", "notice", notice.id)
    db.delete(notice)
    db.commit()
