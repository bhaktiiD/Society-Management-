"""Monthly maintenance billing.

The admin sets a standing rate per flat type (MaintenancePlan) and a due day.
`ensure_billing` turns that into bills:

* one `maintenance` charge per flat per month, from the month billing started
  up to the current month, copying the plan's amount and late fee (snapshot);
* one `late_fee` charge per overdue, still-unpaid bill, once.

It is idempotent (unique indexes + a per-society advisory lock), so it is safe
to call on every request, from several users at once.

shortcut: runs lazily when the app is used, not on a timer. Upgrade to a
scheduled job when there is somewhere free to run one.
"""
import time
from datetime import date

from sqlalchemy import text
from sqlalchemy.orm import Session, aliased

from deps import pick_responsible
from models import Charge, Flat, MaintenancePlan, Society
from payments_service import charge_paid_paise

FLAT_TYPES = ("1RK", "1BHK", "2BHK")  # add a type here and it appears everywhere

_MONTHS = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]


def first_of_month(d: date) -> date:
    return d.replace(day=1)


def add_month(d: date) -> date:
    return date(d.year + (d.month == 12), d.month % 12 + 1, 1)


def month_label(period: date) -> str:
    return f"{_MONTHS[period.month - 1]} {period.year}"


# Every request used to re-run the whole engine: ~20 database round trips. It is
# idempotent, so on the real clock we only need to run it every couple of
# minutes (new months / late fees appear within that delay). Changes that must
# show immediately (rates, flat types, "Generate now") pass force=True.
_MIN_INTERVAL_SECONDS = 120
_last_run: dict[int, float] = {}


def ensure_billing(
    db: Session, society_id: int, today: date | None = None, force: bool = False
) -> dict:
    real_clock = today is None
    if real_clock and not force:
        last = _last_run.get(society_id)
        if last is not None and time.monotonic() - last < _MIN_INTERVAL_SECONDS:
            return {"bills_created": 0, "late_fees_created": 0, "flats_without_owner": 0}
    today = today or date.today()
    society = db.get(Society, society_id)
    if society is None or society.billing_started_on is None:
        return {"bills_created": 0, "late_fees_created": 0, "flats_without_owner": 0}

    # One billing run per society at a time; released at commit/rollback.
    db.execute(text("select pg_advisory_xact_lock(7001, :s)"), {"s": society_id})

    plans = {
        p.flat_type: p
        for p in db.query(MaintenancePlan).filter(MaintenancePlan.society_id == society_id)
    }
    flats = (
        db.query(Flat)
        .filter(Flat.society_id == society_id, Flat.flat_type.isnot(None))
        .order_by(Flat.id)
        .all()
    )

    created = 0
    no_owner = set()
    period = first_of_month(society.billing_started_on)
    while period <= today:
        have = {
            fid
            for (fid,) in db.query(Charge.flat_id).filter(
                Charge.society_id == society_id,
                Charge.charge_type == "maintenance",
                Charge.period == period,
            )
        }
        due = period.replace(day=society.maintenance_due_day)
        for flat in flats:
            plan = plans.get(flat.flat_type)
            if plan is None or flat.id in have:
                continue
            owner = pick_responsible(db, flat.id, "owner")
            if owner is None:
                no_owner.add(flat.id)
                continue
            if first_of_month(owner.start_date) > period:
                continue  # this person did not own the flat yet in that month
            db.add(
                Charge(
                    society_id=society_id,
                    flat_id=flat.id,
                    charge_type="maintenance",
                    title=f"{month_label(period)} maintenance",
                    amount_paise=plan.amount_paise,
                    # Fair play: a bill raised after its due date (billing set up
                    # late, or missed months) never carries a late fee.
                    late_fee_paise=plan.penalty_paise if due >= today else 0,
                    due_date=due,
                    period=period,
                    responsible_user_id=owner.user_id,
                    created_by=None,
                )
            )
            created += 1
        period = add_month(period)
    db.flush()

    # Late fees: overdue bills with a late fee configured, no fee raised yet.
    child = aliased(Charge)
    overdue = (
        db.query(Charge)
        .outerjoin(child, child.parent_charge_id == Charge.id)
        .filter(
            Charge.society_id == society_id,
            Charge.charge_type == "maintenance",
            Charge.late_fee_paise > 0,
            Charge.due_date < today,
            child.id.is_(None),
        )
        .all()
    )
    fees = 0
    for bill in overdue:
        if bill.amount_paise - charge_paid_paise(db, bill.id) <= 0:
            continue  # paid in full before/after due date: no late fee
        db.add(
            Charge(
                society_id=society_id,
                flat_id=bill.flat_id,
                charge_type="late_fee",
                title=f"Late fee: {bill.title}",
                amount_paise=bill.late_fee_paise,
                due_date=today,
                period=bill.period,
                responsible_user_id=bill.responsible_user_id,
                parent_charge_id=bill.id,
                created_by=None,
            )
        )
        fees += 1

    db.commit()
    if real_clock:
        _last_run[society_id] = time.monotonic()
    return {
        "bills_created": created,
        "late_fees_created": fees,
        "flats_without_owner": len(no_owner),
    }
