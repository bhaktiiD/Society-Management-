"""A co-owner of a flat can see and pay the flat's owner-billed bills; nobody else can."""
from datetime import date, timedelta

import models
from tests.test_payments import fake_gateway, make_charge  # noqa: F401  (fixture + helper)


def _add_co_owner(db, world, flat_key="a101", name="coowner"):
    from tests.conftest import Actor

    p = Actor(f"{name}@example.com")
    db.add(models.User(id=p.id, email=p.email, full_name=name))
    db.flush()
    db.add(models.FlatMembership(
        flat_id=world[flat_key], user_id=p.id, kind="owner", is_resident=True,
        start_date=date.today() - timedelta(days=1)))
    db.commit()
    return p


def _intent(client, who, cid, key="key-coowner-1"):
    return client.post("/payments/intents", headers=who.headers,
                       json={"charge_id": cid, "amount_paise": 1000, "idempotency_key": key})


def test_co_owner_sees_and_can_start_paying_owner_billed_charge(client, world, db, fake_gateway):
    cid = make_charge(client, world)          # billed to `owner` of A-101
    co = _add_co_owner(db, world)
    listed = client.get("/charges", headers=co.headers).json()
    assert [c["id"] for c in listed] == [cid]
    assert _intent(client, co, cid).status_code == 200


def test_tenant_billed_charge_stays_with_the_tenant(client, world, db, fake_gateway):
    # B-202 festival charge is billed to the tenant; the landlord (owner) must not pay it.
    r = client.post("/secretary/charges", headers=world["secretary"].headers,
                    json={"flat_id": world["b202"], "charge_type": "festival", "title": "Diwali",
                          "amount_paise": 50_000, "responsible": "tenant", "due_date": str(date.today() + timedelta(days=5))})
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    assert r.json()["responsible_user_id"] == str(world["tenant"].id)
    assert client.get("/charges", headers=world["landlord"].headers).json() == []
    assert _intent(client, world["landlord"], cid).status_code == 404


def test_non_owner_residents_and_other_flats_stay_blocked(client, world, db, fake_gateway):
    cid = make_charge(client, world)
    co_b = _add_co_owner(db, world, flat_key="b202", name="coownerb")
    # owner of ANOTHER flat cannot see A-101's bill
    assert client.get("/charges", headers=co_b.headers).json() == []
    assert _intent(client, co_b, cid, "key-other-flat-1").status_code == 404
    for who in ("tenant", "stranger"):
        assert _intent(client, world[who], cid, f"key-{who}-block").status_code == 404
