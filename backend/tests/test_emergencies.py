from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import update

import models
from routers import emergencies


@pytest.fixture()
def pushes(monkeypatch):
    calls = []

    def rec(db, ids, title, body, data=None, urgent=False):
        calls.append({"ids": set(ids), "title": title, "body": body, "data": data, "urgent": urgent})

    monkeypatch.setattr(emergencies, "notify_users", rec)
    return calls


def raise_(client, who, **body):
    return client.post("/emergencies", json=body, headers=who.headers)


def test_members_can_raise(client, world, pushes):
    for n in ["owner", "tenant", "guard", "secretary"]:
        r = raise_(client, world[n], kind="fire")
        assert r.status_code == 201, n
        assert r.json()["mine"] is True


def test_stranger_403(client, world, pushes):
    r = raise_(client, world["stranger"])
    assert r.status_code == 403
    assert r.json()["detail"] == "You are not part of a society yet."


def test_response_fields(client, world, db, pushes):
    db.execute(update(models.User).where(models.User.id == world["owner"].id).values(phone="999"))
    db.commit()
    j = raise_(client, world["owner"], kind="medical", message="help").json()
    assert j["raised_by_name"] == "owner"
    assert j["flat_number"] == "A-101"
    assert j["phone"] == "999"
    assert j["role_label"] == "Owner"
    assert j["kind_label"] == "Medical"
    assert j["message"] == "help"
    assert j["resolved_at"] is None and j["resolved_by_name"] is None
    assert raise_(client, world["tenant"]).json()["role_label"] == "Tenant"
    g = raise_(client, world["guard"]).json()
    assert g["role_label"] == "Guard" and g["flat_number"] is None
    assert raise_(client, world["secretary"]).json()["role_label"] == "Secretary"
    assert "at the gate" in pushes[-2]["body"]
    assert "from the office" in pushes[-1]["body"]


def test_duplicate_and_push(client, world, pushes):
    r1 = raise_(client, world["owner"], kind="fire")
    r2 = raise_(client, world["owner"], kind="fire")
    assert r1.status_code == 201 and r2.status_code == 200
    assert r1.json()["id"] == r2.json()["id"]
    assert len(pushes) == 1
    p = pushes[0]
    assert p["urgent"] is True
    assert p["title"] == "EMERGENCY - Fire"
    assert p["body"] == "owner, Flat A-101 needs help"
    assert p["data"]["type"] == "emergency" and p["data"]["emergency_id"] == r1.json()["id"]
    expected = {world[n].id for n in ["secretary", "landlord", "tenant", "guard"]}
    assert p["ids"] == expected
    assert world["owner"].id not in p["ids"]
    assert world["secretary2"].id not in p["ids"]


def test_active_list(client, world, pushes):
    eid = raise_(client, world["owner"]).json()["id"]
    for n in ["owner", "tenant", "landlord", "guard", "secretary"]:
        r = client.get("/emergencies/active", headers=world[n].headers)
        assert r.status_code == 200, n
        assert [e["id"] for e in r.json()] == [eid]
    assert client.get("/emergencies/active", headers=world["owner"].headers).json()[0]["mine"] is True
    assert client.get("/emergencies/active", headers=world["tenant"].headers).json()[0]["mine"] is False
    assert client.get("/emergencies/active", headers=world["secretary2"].headers).json() == []
    assert client.get("/emergencies/active", headers=world["stranger"].headers).status_code == 403


def test_resolve(client, world, pushes):
    eid = raise_(client, world["owner"]).json()["id"]
    url = f"/emergencies/{eid}/resolve"
    assert client.post(url, headers=world["tenant"].headers).status_code == 403
    assert client.post(url, headers=world["secretary2"].headers).status_code == 404
    r = client.post(url, headers=world["owner"].headers)
    assert r.status_code == 200 and r.json()["resolved_at"] is not None
    assert r.json()["resolved_by_name"] == "owner"
    again = client.post(url, headers=world["secretary"].headers)
    assert again.status_code == 200
    assert again.json()["resolved_at"] == r.json()["resolved_at"]
    assert client.get("/emergencies/active", headers=world["tenant"].headers).json() == []


def test_resolve_by_admin(client, world, pushes):
    eid = raise_(client, world["tenant"]).json()["id"]
    r = client.post(f"/emergencies/{eid}/resolve", headers=world["secretary"].headers)
    assert r.status_code == 200 and r.json()["resolved_by_name"] == "secretary"
    assert client.get("/emergencies/active", headers=world["owner"].headers).json() == []


def test_old_disappears(client, world, db, pushes):
    eid = raise_(client, world["owner"]).json()["id"]
    db.execute(
        update(models.Emergency)
        .where(models.Emergency.id == eid)
        .values(created_at=datetime.now(timezone.utc) - timedelta(hours=7))
    )
    db.commit()
    assert client.get("/emergencies/active", headers=world["tenant"].headers).json() == []
    # an old unresolved one no longer blocks a fresh alert
    r = raise_(client, world["owner"])
    assert r.status_code == 201 and r.json()["id"] != eid


def test_validation(client, world, pushes):
    assert raise_(client, world["owner"], kind="flood").status_code == 422
    assert raise_(client, world["owner"], message="x" * 201).status_code == 422
    assert raise_(client, world["owner"], message="x" * 200).status_code == 201
    assert raise_(client, world["tenant"]).json()["kind"] == "other"


def test_admin_history(client, world, pushes):
    a = raise_(client, world["owner"]).json()["id"]
    b = raise_(client, world["tenant"]).json()["id"]
    client.post(f"/emergencies/{a}/resolve", headers=world["owner"].headers)
    h = client.get("/secretary/emergencies", headers=world["secretary"].headers)
    assert [e["id"] for e in h.json()] == [b, a]
    assert client.get("/secretary/emergencies", headers=world["owner"].headers).status_code == 403
    assert client.get("/secretary/emergencies", headers=world["secretary2"].headers).json() == []
