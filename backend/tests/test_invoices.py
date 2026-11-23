"""Invoice, society summary and personal ledger endpoints."""
import uuid
from datetime import date, timedelta

from models import Charge, GatewayPayment, PaymentAllocation, PaymentIntent


def add_charge(db, world, flat="a101", *, amount=100_000, title="Nov maintenance",
               ctype="maintenance", days=-3, parent=None, payer="owner", period=None,
               created_by=None):
    c = Charge(
        society_id=world["s1"], flat_id=world[flat], charge_type=ctype, title=title,
        amount_paise=amount, due_date=date.today() + timedelta(days=days),
        responsible_user_id=world[payer].id, parent_charge_id=parent, period=period,
        created_by=created_by,
    )
    db.add(c)
    db.commit()
    return c


def pay(db, world, charge, amount, who="owner", pid=None):
    pid = pid or f"pay_{uuid.uuid4().hex[:12]}"
    intent = PaymentIntent(charge_id=charge.id, user_id=world[who].id, amount_paise=amount,
                           idempotency_key=uuid.uuid4().hex, status="paid")
    db.add(intent)
    db.flush()
    gp = GatewayPayment(intent_id=intent.id, razorpay_payment_id=pid, amount_paise=amount)
    db.add(gp)
    db.flush()
    db.add(PaymentAllocation(gateway_payment_id=gp.id, charge_id=charge.id, amount_paise=amount))
    db.commit()
    return pid


def get(client, world, who, path):
    return client.get(path, headers=world[who].headers)


def test_invoice_paid_partial_unpaid(client, world, db):
    paid = add_charge(db, world, title="Paid bill", days=5)
    pay(db, world, paid, 100_000, pid="pay_ABCDEFGH123456")
    r = get(client, world, "owner", f"/invoices/{paid.id}")
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["status"] == "paid"
    assert (j["total_paise"], j["paid_paise"], j["balance_paise"]) == (100_000, 100_000, 0)
    assert j["payments"][0]["reference"] == "123456"
    assert j["payments"][0]["method"] == "Online"
    assert j["payments"][0]["paid_by_name"] == "owner"
    assert j["flat_number"] == "A-101"
    assert j["billed_to"] == "owner"
    assert j["society"]["name"] == "S1"

    part = add_charge(db, world, title="Partial bill", days=5)
    late = add_charge(db, world, title="Late fee", ctype="late_fee", amount=10_000,
                      parent=part.id, days=5)
    pay(db, world, part, 40_000)
    j = get(client, world, "owner", f"/invoices/{part.id}").json()
    assert j["status"] == "partial"
    assert [i["kind"] for i in j["items"]] == ["maintenance", "late_fee"]
    assert (j["total_paise"], j["paid_paise"], j["balance_paise"]) == (110_000, 40_000, 70_000)
    assert len(j["payments"]) == 1
    assert late.id != part.id

    unpaid = add_charge(db, world, title="Unpaid bill", days=5)
    j = get(client, world, "owner", f"/invoices/{unpaid.id}").json()
    assert j["status"] == "unpaid" and j["payments"] == [] and j["balance_paise"] == 100_000

    over = add_charge(db, world, title="Old bill", days=-20)
    assert get(client, world, "owner", f"/invoices/{over.id}").json()["status"] == "overdue"


def test_invoice_number_format(client, world, db):
    c = add_charge(db, world)
    j = get(client, world, "owner", f"/invoices/{c.id}").json()
    assert j["invoice_number"] == f"INV-{c.created_at.strftime('%Y%m')}-{c.id:05d}"
    assert j["issued_on"] == c.created_at.date().isoformat()


def test_invoice_is_billed_to_the_person_it_was_issued_to(client, world, db):
    c = add_charge(db, world, flat="b202", payer="tenant")
    r = get(client, world, "tenant", f"/invoices/{c.id}")
    assert r.status_code == 200
    assert r.json()["billed_to"] == "tenant"  # the payer, not the landlord
    assert get(client, world, "landlord", f"/invoices/{c.id}").status_code == 200


def test_invoice_404_for_outsiders(client, world, db):
    c = add_charge(db, world)
    assert get(client, world, "tenant", f"/invoices/{c.id}").status_code == 404  # other flat
    assert get(client, world, "secretary2", f"/invoices/{c.id}").status_code == 404  # other society
    assert get(client, world, "stranger", f"/invoices/{c.id}").status_code == 404
    assert get(client, world, "owner", "/invoices/999999").status_code == 404


def test_society_summary_aggregate_only(client, world, db):
    period = date.today().replace(day=1)
    m1 = add_charge(db, world, flat="a101", period=period, amount=100_000)
    m2 = add_charge(db, world, flat="b202", period=period, amount=100_000, payer="tenant")
    pay(db, world, m1, 100_000)
    pay(db, world, m2, 30_000, who="tenant")
    sec = world["secretary"].id
    f1 = add_charge(db, world, flat="a101", ctype="festival", title="Diwali", amount=20_000,
                    created_by=sec)
    add_charge(db, world, flat="b202", ctype="festival", title="Diwali", amount=20_000,
               payer="tenant", created_by=sec)
    pay(db, world, f1, 20_000)

    r = get(client, world, "owner", "/society/summary")
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["society_name"] == "S1" and j["flat_count"] == 2
    assert len(j["months"]) == 1
    m = j["months"][0]
    assert m == {"month": period.strftime("%Y-%m"), "billed_paise": 200_000,
                 "collected_paise": 130_000, "flats_billed": 2, "flats_fully_paid": 1}
    assert len(j["society_charges"]) == 1
    sc = j["society_charges"][0]
    assert (sc["title"], sc["kind"], sc["amount_per_flat_paise"]) == ("Diwali", "festival", 20_000)
    assert (sc["flats_billed"], sc["flats_paid"]) == (2, 1)
    assert j["totals"] == {"collected_all_time_paise": 150_000, "billed_all_time_paise": 240_000}
    for banned in ("A-101", "B-202", "owner", "tenant", "landlord", "example.com"):
        assert banned not in r.text

    # tenant and admin can read too
    assert get(client, world, "tenant", "/society/summary").status_code == 200
    assert get(client, world, "secretary", "/society/summary").json() == j


def test_society_summary_non_member_blocked(client, world):
    assert get(client, world, "stranger", "/society/summary").status_code in (403, 404)


def test_my_ledger_own_flat_newest_first(client, world, db):
    old = add_charge(db, world, title="Old", days=-40)
    new = add_charge(db, world, title="New", days=-3)
    fut = add_charge(db, world, title="Future", days=20)
    pay(db, world, old, 100_000)
    pay(db, world, new, 25_000)
    add_charge(db, world, flat="b202", title="Other flat", payer="tenant")

    r = get(client, world, "owner", "/me/ledger")
    assert r.status_code == 200
    j = r.json()
    assert [g["flat_number"] for g in j] == ["A-101"]
    rows = j[0]["charges"]
    assert [x["id"] for x in rows] == [fut.id, new.id, old.id]
    assert [x["status"] for x in rows] == ["unpaid", "partial", "paid"]
    assert rows[1]["paid_paise"] == 25_000
    assert rows[2]["paid_on"] == date.today().isoformat()
    assert rows[0]["paid_on"] is None
    assert "Other flat" not in r.text
    assert get(client, world, "stranger", "/me/ledger").json() == []
