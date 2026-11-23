from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import Date, case, cast, func, or_
from sqlalchemy.orm import Session, aliased

from billing_service import ensure_billing
from deps import (
    co_owner_payable_flat_ids,
    current_flat_memberships,
    current_user,
    get_db,
    guard_society_ids,
    secretary_society_ids,
    user_flat_ids,
)
from models import (
    Charge,
    Flat,
    FlatMembership,
    GatewayPayment,
    Notice,
    PaymentAllocation,
    PaymentIntent,
    Society,
    User,
)
from routers.secretary import _paid_map, serialize_charge

router = APIRouter(tags=["resident"])

_KINDS = {"maintenance", "late_fee", "festival", "repair"}


def _kind(c: Charge) -> str:
    return c.charge_type if c.charge_type in _KINDS else "other"


def _period(c: Charge):
    return c.period.strftime("%Y-%m") if c.period else None


def _status(total: int, paid: int, due: date) -> str:
    if total - paid <= 0:
        return "paid"
    if paid > 0:
        return "partial"
    return "overdue" if due < date.today() else "unpaid"


def _alloc_stats(db: Session, charge_ids) -> dict[int, tuple[int, datetime]]:
    """charge_id -> (paid_paise, last allocation time)."""
    if not charge_ids:
        return {}
    rows = (
        db.query(
            PaymentAllocation.charge_id,
            func.sum(PaymentAllocation.amount_paise),
            func.max(PaymentAllocation.created_at),
        )
        .filter(PaymentAllocation.charge_id.in_(charge_ids))
        .group_by(PaymentAllocation.charge_id)
        .all()
    )
    return {cid: (int(s), m) for cid, s, m in rows}


@router.get("/invoices/{charge_id}")
def invoice(charge_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    charge = db.get(Charge, charge_id)
    if charge is None or charge.flat_id not in user_flat_ids(db, user.id):
        raise HTTPException(404, "Invoice not found")
    flat = db.get(Flat, charge.flat_id)
    society = db.get(Society, charge.society_id)
    children = (
        db.query(Charge)
        .filter(Charge.parent_charge_id == charge.id)
        .order_by(Charge.id)
        .all()
    )
    lines = [charge] + children
    ids = [c.id for c in lines]

    # "Billed to" is the person this bill was issued to (the snapshotted payer).
    payer = db.get(User, charge.responsible_user_id) if charge.responsible_user_id else None
    billed_to = payer.full_name if payer else user.full_name
    pay_rows = (
        db.query(PaymentAllocation, GatewayPayment, User.full_name)
        .join(GatewayPayment, GatewayPayment.id == PaymentAllocation.gateway_payment_id)
        .join(PaymentIntent, PaymentIntent.id == GatewayPayment.intent_id)
        .join(User, User.id == PaymentIntent.user_id)
        .filter(PaymentAllocation.charge_id.in_(ids))
        .order_by(PaymentAllocation.created_at, PaymentAllocation.id)
        .all()
    )
    total = sum(c.amount_paise for c in lines)
    paid = sum(a.amount_paise for a, _g, _n in pay_rows)
    return {
        "invoice_number": f"INV-{charge.created_at.strftime('%Y%m')}-{charge.id:05d}",
        "issued_on": charge.created_at.date().isoformat(),
        "due_date": charge.due_date.isoformat(),
        "status": _status(total, paid, charge.due_date),
        "society": {"name": society.name, "address": getattr(society, "address", None)},
        "flat_number": flat.flat_number,
        "billed_to": billed_to,
        "items": [
            {
                "title": c.title,
                "kind": _kind(c),
                "period": _period(c),
                "amount_paise": c.amount_paise,
            }
            for c in lines
        ],
        "total_paise": total,
        "paid_paise": paid,
        "balance_paise": total - paid,
        "payments": [
            {
                "paid_on": a.created_at.isoformat(),
                "amount_paise": a.amount_paise,
                "method": "Online",
                "reference": g.razorpay_payment_id[-6:] if g.razorpay_payment_id else None,
                "paid_by_name": name,
            }
            for a, g, name in pay_rows
        ],
    }


@router.get("/society/summary")
def society_summary(user: User = Depends(current_user), db: Session = Depends(get_db)):
    ids = secretary_society_ids(db, user.id) or [
        m.flat.society_id for m in current_flat_memberships(db, user.id)
    ]
    if not ids:
        raise HTTPException(403, "Not a member of any society")
    sid = ids[0]
    society = db.get(Society, sid)
    flat_count = db.query(func.count(Flat.id)).filter(Flat.society_id == sid).scalar() or 0

    paid_sq = (
        db.query(
            PaymentAllocation.charge_id.label("cid"),
            func.sum(PaymentAllocation.amount_paise).label("paid"),
        )
        .group_by(PaymentAllocation.charge_id)
        .subquery()
    )
    paid_col = func.coalesce(paid_sq.c.paid, 0)
    parent = aliased(Charge)

    # Monthly maintenance (late fees count toward the month of their parent bill).
    month_col = func.to_char(
        func.coalesce(parent.period, Charge.period, parent.due_date, Charge.due_date), "YYYY-MM"
    )
    mrows = (
        db.query(
            month_col,
            Charge.flat_id,
            func.sum(Charge.amount_paise),
            func.sum(paid_col),
        )
        .outerjoin(parent, parent.id == Charge.parent_charge_id)
        .outerjoin(paid_sq, paid_sq.c.cid == Charge.id)
        .filter(Charge.society_id == sid, Charge.charge_type.in_(("maintenance", "late_fee")))
        .group_by(month_col, Charge.flat_id)
        .all()
    )
    months: dict[str, dict] = {}
    for m, _flat, billed, coll in mrows:
        row = months.setdefault(
            m,
            {"month": m, "billed_paise": 0, "collected_paise": 0, "flats_billed": 0, "flats_fully_paid": 0},
        )
        billed, coll = int(billed), int(coll)
        row["billed_paise"] += billed
        row["collected_paise"] += coll
        row["flats_billed"] += 1
        row["flats_fully_paid"] += 1 if coll >= billed else 0
    month_list = sorted(months.values(), key=lambda r: r["month"], reverse=True)[:12]

    created_day = cast(Charge.created_at, Date)
    srows = (
        db.query(
            func.min(Charge.id),
            Charge.title,
            Charge.charge_type,
            func.min(Charge.amount_paise),
            func.min(Charge.due_date),
            func.min(Charge.created_at),
            func.count(func.distinct(Charge.flat_id)),
            func.sum(case((paid_col >= Charge.amount_paise, 1), else_=0)),
        )
        .outerjoin(paid_sq, paid_sq.c.cid == Charge.id)
        .filter(
            Charge.society_id == sid,
            Charge.charge_type.notin_(("maintenance", "late_fee")),
        )
        .group_by(Charge.title, Charge.charge_type, Charge.created_by, created_day)
        .order_by(func.max(Charge.created_at).desc(), func.min(Charge.id).desc())
        .limit(24)
        .all()
    )
    billed_all = (
        db.query(func.coalesce(func.sum(Charge.amount_paise), 0))
        .filter(Charge.society_id == sid)
        .scalar()
    )
    collected_all = (
        db.query(func.coalesce(func.sum(PaymentAllocation.amount_paise), 0))
        .join(Charge, Charge.id == PaymentAllocation.charge_id)
        .filter(Charge.society_id == sid)
        .scalar()
    )
    return {
        "society_name": society.name,
        "flat_count": flat_count,
        "months": month_list,
        "society_charges": [
            {
                "id": i,
                "title": title,
                "kind": ctype,
                "amount_per_flat_paise": int(amt),
                "due_date": due.isoformat(),
                "created_at": created.isoformat(),
                "flats_billed": int(nb),
                "flats_paid": int(npaid or 0),
            }
            for i, title, ctype, amt, due, created, nb, npaid in srows
        ],
        "totals": {
            "collected_all_time_paise": int(collected_all),
            "billed_all_time_paise": int(billed_all),
        },
    }


@router.get("/me/ledger")
def my_ledger(user: User = Depends(current_user), db: Session = Depends(get_db)):
    flat_ids = user_flat_ids(db, user.id)
    if not flat_ids:
        return []
    flats = db.query(Flat).filter(Flat.id.in_(flat_ids)).order_by(Flat.flat_number).all()
    rn = (
        func.row_number()
        .over(partition_by=Charge.flat_id, order_by=(Charge.due_date.desc(), Charge.id.desc()))
        .label("rn")
    )
    sub = db.query(Charge.id.label("cid"), rn).filter(Charge.flat_id.in_(flat_ids)).subquery()
    charges = (
        db.query(Charge)
        .join(sub, sub.c.cid == Charge.id)
        .filter(sub.c.rn <= 200)
        .order_by(Charge.due_date.desc(), Charge.id.desc())
        .all()
    )
    stats = _alloc_stats(db, [c.id for c in charges])
    by_flat: dict[int, list] = {f.id: [] for f in flats}
    for c in charges:
        paid, last = stats.get(c.id, (0, None))
        by_flat[c.flat_id].append(
            {
                "id": c.id,
                "title": c.title,
                "kind": _kind(c),
                "period": _period(c),
                "due_date": c.due_date.isoformat(),
                "amount_paise": c.amount_paise,
                "paid_paise": paid,
                "status": _status(c.amount_paise, paid, c.due_date),
                "paid_on": last.date().isoformat() if last else None,
            }
        )
    return [{"flat_number": f.flat_number, "charges": by_flat[f.id]} for f in flats]


@router.get("/charges")
def my_charges(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """My bills: where I am the snapshotted payer, or a co-owner of the flat the bill was billed to."""
    for society_id in {m.flat.society_id for m in current_flat_memberships(db, user.id)}:
        ensure_billing(db, society_id)  # bring monthly bills / late fees up to date
    # My own bills, plus bills of a flat I co-own that were billed to another
    # owner of it (any owner may pay the household's dues).
    owner_flats = user_flat_ids(db, user.id, only_owners=True)
    cond = Charge.responsible_user_id == user.id
    if owner_flats:
        cond = or_(cond, Charge.flat_id.in_(owner_flats))
    candidates = db.query(Charge).filter(cond).order_by(Charge.due_date.desc(), Charge.id.desc()).all()
    allowed = co_owner_payable_flat_ids(db, user.id, candidates)
    charges = [c for c in candidates if c.responsible_user_id == user.id or c.id in allowed]
    paid = _paid_map(db, [c.id for c in charges])
    flats = {f.id: f.flat_number for f in db.query(Flat).filter(Flat.id.in_({c.flat_id for c in charges}))} if charges else {}
    out = []
    for c in charges:
        row = serialize_charge(c, paid.get(c.id, 0))
        row["flat_number"] = flats.get(c.flat_id)
        out.append(row)
    return out


@router.get("/notices")
def notices(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Notices of every society I currently belong to (any role)."""
    society_ids = set(secretary_society_ids(db, user.id)) | set(guard_society_ids(db, user.id))
    society_ids |= {m.flat.society_id for m in current_flat_memberships(db, user.id)}
    if not society_ids:
        return []
    rows = (
        db.query(Notice)
        .filter(Notice.society_id.in_(society_ids))
        .order_by(Notice.pinned.desc(), Notice.created_at.desc())
        .limit(100)
        .all()
    )
    return [
        {
            "id": n.id,
            "title": n.title,
            "body": n.body,
            "pinned": n.pinned,
            "created_at": n.created_at.isoformat(),
        }
        for n in rows
    ]


@router.get("/payments/history")
def payment_history(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = (
        db.query(GatewayPayment, PaymentIntent, Charge)
        .join(PaymentIntent, PaymentIntent.id == GatewayPayment.intent_id)
        .join(Charge, Charge.id == PaymentIntent.charge_id)
        .filter(PaymentIntent.user_id == user.id)
        .order_by(GatewayPayment.verified_at.desc())
        .limit(100)
        .all()
    )
    return [
        {
            "payment_id": gp.razorpay_payment_id,
            "amount_paise": gp.amount_paise,
            "charge_title": ch.title,
            "paid_at": gp.verified_at.isoformat(),
        }
        for gp, _intent, ch in rows
    ]
