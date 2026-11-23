"""Society-wide festival / repair charges are billed to every flat."""
from datetime import date, timedelta

from models import Charge

DUE = str(date.today() + timedelta(days=10))


def broadcast(client, who, **over):
    body = {"charge_type": "festival", "title": "Diwali", "amount_paise": 50000, "due_date": DUE}
    body.update(over)
    return client.post("/secretary/charges", headers=who.headers, json=body)


def test_charge_without_flat_bills_every_flat_in_the_society(client, world, db):
    r = broadcast(client, world["secretary"])
    assert r.status_code == 201
    assert r.json()["created"] == 2 and r.json()["skipped_flats"] == []
    rows = db.query(Charge).filter(Charge.title == "Diwali").all()
    assert {c.flat_id for c in rows} == {world["a101"], world["b202"]}
    assert all(c.amount_paise == 50000 for c in rows)
    # Other societies are never touched.
    assert all(c.society_id == world["s1"] for c in rows)


def test_who_pays_decides_owner_or_tenant_per_flat(client, world, db):
    broadcast(client, world["secretary"], title="Owner pays", responsible="owner")
    broadcast(client, world["secretary"], title="Tenant pays", responsible="tenant")
    owner_pays = {c.flat_id: c.responsible_user_id for c in db.query(Charge).filter(Charge.title == "Owner pays")}
    tenant_pays = {c.flat_id: c.responsible_user_id for c in db.query(Charge).filter(Charge.title == "Tenant pays")}
    assert owner_pays[world["b202"]] == world["landlord"].id
    assert tenant_pays[world["b202"]] == world["tenant"].id
    # a101 has no tenant: the owner is billed instead rather than skipping the flat.
    assert tenant_pays[world["a101"]] == world["owner"].id


def test_billed_owner_instead_is_reported(client, world):
    r = broadcast(client, world["secretary"], responsible="tenant")
    assert r.json()["billed_owner_instead"] == 1


def test_flats_with_nobody_registered_are_skipped_and_listed(client, world):
    client.post("/secretary/flats", headers=world["secretary"].headers, json={"flat_number": "C-9"})
    r = broadcast(client, world["secretary"])
    assert r.json()["created"] == 2 and r.json()["skipped_flats"] == ["C-9"]


def test_same_society_wide_charge_cannot_be_created_twice(client, world, db):
    assert broadcast(client, world["secretary"]).status_code == 201
    assert broadcast(client, world["secretary"]).status_code == 409
    assert db.query(Charge).filter(Charge.title == "Diwali").count() == 2   # not 4
    # A different title or due date is a new charge.
    assert broadcast(client, world["secretary"], title="Diwali dinner").status_code == 201


def test_nothing_to_bill_returns_422(client, world):
    # secretary2's society has one flat and nobody registered in it.
    assert broadcast(client, world["secretary2"]).status_code == 422


def test_maintenance_cannot_be_broadcast_manually(client, world):
    assert broadcast(client, world["secretary"], charge_type="maintenance").status_code == 422


def test_only_admin_can_create_society_wide_charges(client, world):
    for who in ("owner", "tenant", "guard", "stranger"):
        assert broadcast(client, world[who]).status_code == 403


def test_residents_see_their_share(client, world):
    broadcast(client, world["secretary"], responsible="tenant")
    mine = client.get("/charges", headers=world["tenant"].headers).json()
    assert len(mine) == 1 and mine[0]["amount_paise"] == 50000 and mine[0]["charge_type"] == "festival"
    assert client.get("/charges", headers=world["landlord"].headers).json() == []


def test_single_flat_charge_still_works(client, world):
    r = client.post("/secretary/charges", headers=world["secretary"].headers, json={
        "flat_id": world["a101"], "charge_type": "repair", "title": "Pump", "amount_paise": 1000, "due_date": DUE})
    assert r.status_code == 201 and "responsible_user_id" in r.json()
