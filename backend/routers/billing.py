"""Admin settings for monthly maintenance: rate + late fee per flat type, due day."""
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from billing_service import FLAT_TYPES, ensure_billing, first_of_month
from deps import SocietyContext, audit, get_db, require_secretary
from models import Flat, MaintenancePlan, Society

router = APIRouter(prefix="/secretary/billing", tags=["billing"])

_MAX_PAISE = 100_000_000  # Rs 10 lakh


@router.get("")
def get_settings(ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)):
    """What is currently set. A type with no plan yet has null amounts."""
    society = db.get(Society, ctx.society_id)
    plans = {
        p.flat_type: p
        for p in db.query(MaintenancePlan).filter(MaintenancePlan.society_id == ctx.society_id)
    }
    untyped = (
        db.query(func.count(Flat.id))
        .filter(Flat.society_id == ctx.society_id, Flat.flat_type.is_(None))
        .scalar()
    )
    return {
        "due_day": society.maintenance_due_day,
        "untyped_flats": untyped,
        "plans": [
            {
                "flat_type": t,
                "amount_paise": plans[t].amount_paise if t in plans else None,
                "penalty_paise": plans[t].penalty_paise if t in plans else None,
            }
            for t in FLAT_TYPES
        ],
    }


class PlanIn(BaseModel):
    amount_paise: int = Field(gt=0, le=_MAX_PAISE)
    penalty_paise: int = Field(ge=0, le=_MAX_PAISE)


@router.put("/plans/{flat_type}")
def set_plan(
    flat_type: str,
    body: PlanIn,
    ctx: SocietyContext = Depends(require_secretary),
    db: Session = Depends(get_db),
):
    """Create or change the standing rate for a flat type.

    Applies to bills created from now on. Bills already issued keep the rate
    they were issued at.
    """
    if flat_type not in FLAT_TYPES:
        raise HTTPException(404, "Please choose a valid flat type.")
    plan = (
        db.query(MaintenancePlan)
        .filter_by(society_id=ctx.society_id, flat_type=flat_type)
        .first()
    )
    if plan is None:
        plan = MaintenancePlan(society_id=ctx.society_id, flat_type=flat_type)
        db.add(plan)
    plan.amount_paise = body.amount_paise
    plan.penalty_paise = body.penalty_paise
    plan.updated_by = ctx.user.id

    society = db.get(Society, ctx.society_id)
    if society.billing_started_on is None:
        society.billing_started_on = first_of_month(date.today())  # billing starts this month
    audit(
        db, ctx.user, ctx.society_id, "billing.plan_set", "maintenance_plan", f"{ctx.society_id}:{flat_type}",
        {"amount_paise": body.amount_paise, "penalty_paise": body.penalty_paise},
    )
    db.commit()
    return {"flat_type": flat_type, **ensure_billing(db, ctx.society_id, force=True)}


class DueDayIn(BaseModel):
    due_day: int = Field(ge=1, le=28)  # 28 so every month has that day


@router.put("/due-day")
def set_due_day(
    body: DueDayIn, ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)
):
    """Day of month bills fall due. Affects bills created from now on."""
    society = db.get(Society, ctx.society_id)
    society.maintenance_due_day = body.due_day
    audit(db, ctx.user, ctx.society_id, "billing.due_day_set", "society", ctx.society_id, {"due_day": body.due_day})
    db.commit()
    return {"due_day": body.due_day}


@router.post("/run")
def run_billing(ctx: SocietyContext = Depends(require_secretary), db: Session = Depends(get_db)):
    """Generate any missing monthly bills and late fees now."""
    return ensure_billing(db, ctx.society_id, force=True)
