"""Monthly maintenance: standing rates per flat type, auto bills, late fees.

Generation tests inject a fixed `today` (Jan 2030) so they never depend on the
real date. Plans are written straight to the DB there; the API is covered by
the settings/validation tests.
"""
from datetime import date, timedelta

from billing_service import add_month, ensure_billing, first_of_month
from models import (
    Charge,
    Flat,
    GatewayPayment,
    MaintenancePlan,
    PaymentAllocation,
    PaymentIntent,
    Society,
)

TODAY = date(2030, 1, 5)            # before the 10th: bills are issued on time
JAN = first_of_month(TODAY)
FEB = add_month(JAN)


def seed_rates(db, world, today=TODAY, due_day=10):
    """a101 = 2BHK Rs3000 (late fee Rs200), b202 = 1BHK Rs2000 (late fee Rs150)."""
    society = db.get(Society, world["s1"])
    society.maintenance_due_day = due_day
    society.billing_started_on = first_of_month(today)
    db.get(Flat, world["a101"]).flat_type = "2BHK"
    db.get(Flat, world["b202"]).flat_type = "1BHK"
    db.add_all([
        MaintenancePlan(society_id=world["s1"], flat_type="2BHK", amount_paise=300000, penalty_paise=20000),
        MaintenancePlan(society_id=world["s1"], flat_type="1BHK", amount_paise=200000, penalty_paise=15000),
    ])
    db.commit()
    return ensure_billing(db, world["s1"], today=today)


def charges(db, kind="maintenance"):
    db.expire_all()
    return db.query(Charge).filter(Charge.charge_type == kind).order_by(Charge.id).all()


def pay_fully(db, charge):
    intent = PaymentIntent(charge_id=charge.id, user_id=charge.responsible_user_id,
                           amount_paise=charge.amount_paise, idempotency_key=f"k{charge.id}-xxxxxxxx",
                           razorpay_order_id=f"order_{charge.id}", status="paid")
    db.add(intent)
    db.flush()
    gp = GatewayPayment(intent_id=intent.id, razorpay_payment_id=f"pay_{charge.id}",
                        amount_paise=charge.amount_paise)
    db.add(gp)
    db.flush()
    db.add(PaymentAllocation(gateway_payment_id=gp.id, charge_id=charge.id, amount_paise=charge.amount_paise))
    db.commit()


# ------------------------------------------------------------- settings API
def test_settings_show_unset_then_saved_values(client, world):
    h = world["secretary"].headers
    first = client.get("/secretary/billing", headers=h).json()
    assert first["due_day"] == 10
    assert [p["flat_type"] for p in first["plans"]] == ["1RK", "1BHK", "2BHK"]
    assert all(p["amount_paise"] is None for p in first["plans"])
    assert first["untyped_flats"] == 2

    client.put(f"/secretary/flats/{world['a101']}/type", headers=h, json={"flat_type": "2BHK"})
    client.put("/secretary/billing/plans/2BHK", headers=h, json={"amount_paise": 300000, "penalty_paise": 20000})
    second = client.get("/secretary/billing", headers=h).json()
    plans = {p["flat_type"]: p for p in second["plans"]}
    assert plans["2BHK"] == {"flat_type": "2BHK", "amount_paise": 300000, "penalty_paise": 20000}
    assert plans["1RK"]["amount_paise"] is None
    assert second["untyped_flats"] == 1


def test_rate_edit_persists_and_is_shown_back(client, world):
    h = world["secretary"].headers
    client.put("/secretary/billing/plans/2BHK", headers=h, json={"amount_paise": 300000, "penalty_paise": 20000})
    client.put("/secretary/billing/plans/2BHK", headers=h, json={"amount_paise": 350000, "penalty_paise": 25000})
    plans = {p["flat_type"]: p for p in client.get("/secretary/billing", headers=h).json()["plans"]}
    assert (plans["2BHK"]["amount_paise"], plans["2BHK"]["penalty_paise"]) == (350000, 25000)


def test_billing_endpoints_validate_and_are_admin_only(client, world):
    h = world["secretary"].headers
    for who in ("owner", "tenant", "guard", "stranger"):
        assert client.get("/secretary/billing", headers=world[who].headers).status_code == 403
        assert client.put("/secretary/billing/plans/2BHK", headers=world[who].headers,
                          json={"amount_paise": 1, "penalty_paise": 0}).status_code == 403
    assert client.put("/secretary/billing/plans/3BHK", headers=h,
                      json={"amount_paise": 100, "penalty_paise": 0}).status_code == 404
    for bad in ({"amount_paise": 0, "penalty_paise": 0},
                {"amount_paise": 1000.5, "penalty_paise": 0},
                {"amount_paise": 1000, "penalty_paise": -1}):
        assert client.put("/secretary/billing/plans/2BHK", headers=h, json=bad).status_code == 422
    assert client.put("/secretary/billing/due-day", headers=h, json={"due_day": 31}).status_code == 422
    assert client.put("/secretary/billing/due-day", headers=h, json={"due_day": 0}).status_code == 422
    assert client.put(f"/secretary/flats/{world['a101']}/type", headers=h,
                      json={"flat_type": "PENTHOUSE"}).status_code == 422


def test_cannot_type_another_societys_flat(client, world):
    r = client.put(f"/secretary/flats/{world['a101']}/type", headers=world["secretary2"].headers,
                   json={"flat_type": "1RK"})
    assert r.status_code == 404


def test_resident_gets_generated_bill_via_api(client, world, db):
    """End to end on the real date: set rates, owner sees a maintenance bill."""
    h = world["secretary"].headers
    client.put("/secretary/billing/due-day", headers=h, json={"due_day": 28})
    client.put(f"/secretary/flats/{world['a101']}/type", headers=h, json={"flat_type": "2BHK"})
    client.put("/secretary/billing/plans/2BHK", headers=h, json={"amount_paise": 300000, "penalty_paise": 20000})
    mine = [c for c in client.get("/charges", headers=world["owner"].headers).json()
            if c["charge_type"] == "maintenance"]
    assert len(mine) == 1 and mine[0]["amount_paise"] == 300000
    assert client.get("/charges", headers=world["tenant"].headers).json() == []


# --------------------------------------------------------------- generation
def test_monthly_bills_use_flat_type_rate_and_bill_the_owner(client, world, db):
    assert seed_rates(db, world)["bills_created"] == 2
    by_flat = {c.flat_id: c for c in charges(db)}
    assert by_flat[world["a101"]].amount_paise == 300000                       # 2BHK
    assert by_flat[world["b202"]].amount_paise == 200000                       # 1BHK
    assert by_flat[world["b202"]].responsible_user_id == world["landlord"].id  # owner, not tenant
    assert by_flat[world["a101"]].period == JAN
    assert by_flat[world["a101"]].due_date == date(2030, 1, 10)
    assert by_flat[world["a101"]].late_fee_paise == 20000
    assert "January 2030" in by_flat[world["a101"]].title


def test_billing_is_idempotent(client, world, db):
    seed_rates(db, world)
    for _ in range(3):
        ensure_billing(db, world["s1"], today=TODAY)
    assert len(charges(db)) == 2


def test_next_month_bills_appear_without_admin_action(client, world, db):
    seed_rates(db, world)
    assert ensure_billing(db, world["s1"], today=FEB)["bills_created"] == 2
    assert len(charges(db)) == 4


def test_missed_months_are_caught_up(client, world, db):
    seed_rates(db, world)
    ensure_billing(db, world["s1"], today=date(2030, 4, 2))   # nobody opened the app for 3 months
    periods = sorted({c.period for c in charges(db)})
    assert periods == [date(2030, m, 1) for m in (1, 2, 3, 4)]


def test_rate_change_only_affects_future_bills(client, world, db):
    seed_rates(db, world)
    client.put("/secretary/billing/plans/2BHK", headers=world["secretary"].headers,
               json={"amount_paise": 350000, "penalty_paise": 30000})
    ensure_billing(db, world["s1"], today=FEB)
    a101 = sorted([c for c in charges(db) if c.flat_id == world["a101"]], key=lambda c: c.period)
    assert [c.amount_paise for c in a101] == [300000, 350000]     # old bill untouched
    assert [c.late_fee_paise for c in a101] == [20000, 30000]


def test_due_day_change_applies_to_new_bills_only(client, world, db):
    seed_rates(db, world, due_day=10)
    client.put("/secretary/billing/due-day", headers=world["secretary"].headers, json={"due_day": 20})
    ensure_billing(db, world["s1"], today=FEB)
    a101 = sorted([c for c in charges(db) if c.flat_id == world["a101"]], key=lambda c: c.period)
    assert (a101[0].due_date.day, a101[1].due_date.day) == (10, 20)


def test_untyped_flats_and_flats_without_owner_are_skipped(client, world, db):
    h = world["secretary"].headers
    seed_rates(db, world)
    client.post("/secretary/flats", headers=h, json={"flat_number": "C-1", "flat_type": "1BHK"})  # no owner
    client.post("/secretary/flats", headers=h, json={"flat_number": "C-2"})                       # no type
    out = ensure_billing(db, world["s1"], today=TODAY)
    assert out["bills_created"] == 0 and out["flats_without_owner"] == 1
    assert len(charges(db)) == 2


def test_billing_not_started_until_a_plan_exists(client, world, db):
    db.get(Flat, world["a101"]).flat_type = "2BHK"
    db.commit()
    assert ensure_billing(db, world["s1"], today=TODAY)["bills_created"] == 0
    assert charges(db) == []


# --------------------------------------------------------------- late fees
def test_late_fee_charged_once_when_overdue_and_unpaid(client, world, db):
    seed_rates(db, world)
    assert ensure_billing(db, world["s1"], today=date(2030, 1, 10))["late_fees_created"] == 0  # due day itself
    first = ensure_billing(db, world["s1"], today=date(2030, 1, 11))
    ensure_billing(db, world["s1"], today=date(2030, 2, 1))
    fees = charges(db, "late_fee")
    assert first["late_fees_created"] == 2
    assert len({f.parent_charge_id for f in fees}) == len(fees)           # one fee per bill, ever
    a101_fee = [f for f in fees if f.flat_id == world["a101"]][0]
    assert a101_fee.amount_paise == 20000 and a101_fee.responsible_user_id == world["owner"].id


def test_no_late_fee_for_a_paid_bill(client, world, db):
    seed_rates(db, world)
    pay_fully(db, [c for c in charges(db) if c.flat_id == world["a101"]][0])
    ensure_billing(db, world["s1"], today=date(2030, 1, 15))
    assert [f.flat_id for f in charges(db, "late_fee")] == [world["b202"]]   # only the unpaid flat


def test_late_fee_uses_penalty_from_when_bill_was_issued(client, world, db):
    seed_rates(db, world)
    client.put("/secretary/billing/plans/2BHK", headers=world["secretary"].headers,
               json={"amount_paise": 300000, "penalty_paise": 99000})    # changed AFTER the bill exists
    ensure_billing(db, world["s1"], today=date(2030, 1, 11))
    fee = [f for f in charges(db, "late_fee") if f.flat_id == world["a101"]][0]
    assert fee.amount_paise == 20000


def test_zero_penalty_means_no_late_fee(client, world, db):
    seed_rates(db, world)
    for p in db.query(MaintenancePlan):
        p.penalty_paise = 0
    for c in charges(db):
        c.late_fee_paise = 0
    db.commit()
    ensure_billing(db, world["s1"], today=date(2030, 1, 20))
    assert charges(db, "late_fee") == []


def test_bill_raised_after_its_due_date_carries_no_late_fee(client, world, db):
    """Admin sets rates on the 22nd: this month's bill is not instantly penalised."""
    seed_rates(db, world, today=date(2030, 1, 22))
    assert all(c.late_fee_paise == 0 for c in charges(db))
    ensure_billing(db, world["s1"], today=date(2030, 1, 25))
    assert charges(db, "late_fee") == []
    ensure_billing(db, world["s1"], today=date(2030, 2, 3))     # but next month is on time
    feb = [c for c in charges(db) if c.period == FEB]
    assert all(c.late_fee_paise > 0 for c in feb)


def test_late_fee_shows_in_residents_bills(client, world, db):
    seed_rates(db, world)
    ensure_billing(db, world["s1"], today=date(2030, 1, 11))
    mine = client.get("/charges", headers=world["owner"].headers).json()
    assert any(c["title"].startswith("Late fee") for c in mine)
    assert sum(c["balance_paise"] for c in mine) == 300000 + 20000


def test_new_owner_is_not_billed_for_months_before_they_owned_the_flat(client, world, db):
    """Billing started 3 months ago, but the owner only joined today: one bill, not four."""
    from datetime import timedelta
    from models import FlatMembership
    today = date.today()
    start = first_of_month(today)
    for _ in range(3):
        start = (start - timedelta(days=1)).replace(day=1)
    society = db.get(Society, world["s1"])
    society.billing_started_on = start
    society.maintenance_due_day = 10
    db.get(Flat, world["a101"]).flat_type = "2BHK"
    db.add(MaintenancePlan(society_id=world["s1"], flat_type="2BHK", amount_paise=300000, penalty_paise=0))
    membership = db.query(FlatMembership).filter_by(flat_id=world["a101"], user_id=world["owner"].id).one()
    membership.start_date = today                      # moved in today
    db.commit()
    ensure_billing(db, world["s1"])
    periods = [c.period for c in charges(db) if c.flat_id == world["a101"]]
    assert periods == [first_of_month(today)]


def test_collections_card_is_maintenance_only_and_overdue_flats_name_the_owner(client, world, db):
    """Home shows 'Maintenance collected' (monthly bills + late fees only) and each
    overdue flat carries its id and owner's name so the admin can open it."""
    h = world["secretary"].headers
    # A society charge that is already overdue must NOT count towards maintenance totals.
    r = client.post("/secretary/charges", headers=h, json={
        "flat_id": world["a101"], "charge_type": "festival", "title": "Diwali",
        "amount_paise": 50_000, "due_date": str(date.today() - timedelta(days=3))})
    assert r.status_code == 201
    out = client.get("/secretary/collections", headers=h).json()
    assert out["maintenance"] == {"billed_paise": 0, "collected_paise": 0, "outstanding_paise": 0}
    assert out["billed_paise"] == 50_000                       # overall total still includes it
    d = out["defaulters"][0]
    assert d["flat_id"] == world["a101"] and d["flat_number"] == "A-101"
    assert d["owner_name"] == "owner" and d["overdue_paise"] == 50_000
