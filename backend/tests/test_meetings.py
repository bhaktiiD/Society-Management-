from datetime import date, datetime, timedelta, timezone

import uuid

import models


def _when(days=3, hours=0):
    return (datetime.now(timezone.utc) + timedelta(days=days, hours=hours)).isoformat()


def _create(client, w, who="secretary", **over):
    body = {"title": "AGM", "scheduled_at": _when(), **over}
    return client.post("/secretary/meetings", json=body, headers=w[who].headers)


def _mine(client, w, who):
    r = client.get("/meetings", headers=w[who].headers)
    assert r.status_code == 200
    return r.json()


def _insert(db, w, days, title="Old", audience="everyone", cancelled=False, society="s1"):
    m = models.Meeting(
        society_id=w[society], title=title, scheduled_at=datetime.now(timezone.utc) + timedelta(days=days),
        audience=audience, created_by=w["secretary"].id,
        cancelled_at=datetime.now(timezone.utc) if cancelled else None,
    )
    db.add(m)
    db.commit()
    return m.id


def test_admin_create_and_list(client, world):
    r = _create(client, world, title="  AGM  ", agenda="Budget", location="Hall")
    assert r.status_code == 201
    j = r.json()
    assert j["title"] == "AGM" and j["status"] == "upcoming" and j["audience"] == "everyone"
    assert j["agenda"] == "Budget" and j["location"] == "Hall" and j["cancelled_at"] is None
    assert j["invited_count"] == 3
    lst = client.get("/secretary/meetings", headers=world["secretary"].headers).json()
    assert [m["id"] for m in lst] == [j["id"]]


def test_everyone_visible_to_all_members(client, world):
    _create(client, world)
    for who in ("owner", "tenant", "landlord"):
        assert len(_mine(client, world, who)) == 1
    for who in ("stranger", "guard"):
        assert _mine(client, world, who) == []


def test_owners_only(client, world):
    j = _create(client, world, audience="owners").json()
    assert j["invited_count"] == 2
    assert len(_mine(client, world, "owner")) == 1
    assert len(_mine(client, world, "landlord")) == 1
    assert _mine(client, world, "tenant") == []
    assert _mine(client, world, "stranger") == []


def test_cancel_idempotent_and_visibility(client, world):
    mid = _create(client, world).json()["id"]
    h = world["secretary"].headers
    r1 = client.post(f"/secretary/meetings/{mid}/cancel", headers=h)
    assert r1.status_code == 200 and r1.json()["status"] == "cancelled"
    r2 = client.post(f"/secretary/meetings/{mid}/cancel", headers=h)
    assert r2.json()["cancelled_at"] == r1.json()["cancelled_at"]
    mine = _mine(client, world, "owner")
    assert [m["status"] for m in mine] == ["cancelled"]


def test_old_cancelled_hidden_from_residents(client, world, db):
    _insert(db, world, -40, cancelled=True)
    _insert(db, world, -40)
    _insert(db, world, -10, title="Recent")
    mine = _mine(client, world, "owner")
    assert [m["title"] for m in mine] == ["Recent"]
    assert len(client.get("/secretary/meetings", headers=world["secretary"].headers).json()) == 3


def test_non_admin_403(client, world):
    for who in ("owner", "tenant", "guard", "stranger"):
        h = world[who].headers
        assert client.post("/secretary/meetings", json={"title": "x", "scheduled_at": _when()}, headers=h).status_code == 403
        assert client.get("/secretary/meetings", headers=h).status_code == 403
        assert client.post("/secretary/meetings/1/cancel", headers=h).status_code == 403


def test_validation(client, world):
    assert _create(client, world, scheduled_at=_when(-1)).status_code == 422
    assert _create(client, world, scheduled_at=_when(366)).status_code == 422
    assert _create(client, world, title="   ").status_code == 422
    assert _create(client, world, title="x" * 151).status_code == 422
    assert _create(client, world, agenda="x" * 2001).status_code == 422
    assert _create(client, world, location="x" * 151).status_code == 422
    assert _create(client, world, audience="tenants").status_code == 422
    assert _create(client, world, scheduled_at="garbage").status_code == 422
    assert _create(client, world, agenda="x" * 2000, location="y" * 150).status_code == 201


def test_naive_datetime_is_utc(client, world):
    naive = (datetime.now(timezone.utc) + timedelta(days=2)).replace(tzinfo=None, microsecond=0)
    j = _create(client, world, scheduled_at=naive.isoformat()).json()
    got = datetime.fromisoformat(j["scheduled_at"])
    assert got.utcoffset() == timedelta(0)
    assert got.replace(tzinfo=None) == naive


def test_ordering_and_status(client, world, db):
    far = _create(client, world, title="far", scheduled_at=_when(20)).json()["id"]
    near = _create(client, world, title="near", scheduled_at=_when(2)).json()["id"]
    old1 = _insert(db, world, -2, title="old1")
    old2 = _insert(db, world, -5, title="old2")
    for url, who in (("/secretary/meetings", "secretary"), ("/meetings", "owner")):
        lst = client.get(url, headers=world[who].headers).json()
        assert [m["id"] for m in lst] == [near, far, old1, old2]
        assert [m["status"] for m in lst] == ["upcoming", "upcoming", "past", "past"]


def test_cross_society(client, world, db):
    mid = _create(client, world).json()["id"]
    h2 = world["secretary2"].headers
    assert client.get("/secretary/meetings", headers=h2).json() == []
    assert client.post(f"/secretary/meetings/{mid}/cancel", headers=h2).status_code == 404
    assert client.post("/secretary/meetings/99999/cancel", headers=h2).status_code == 404
    # a resident of society 2 sees nothing
    u = models.User(id=uuid.uuid4(), email="x2@example.com", full_name="x2")
    db.add(u)
    db.flush()
    db.add(models.FlatMembership(flat_id=world["x1"], user_id=u.id, kind="owner",
                                 is_resident=True, start_date=date.today() - timedelta(days=5)))
    db.commit()
    hx = {"x-test-sub": str(u.id), "x-test-email": u.email}
    assert client.get("/meetings", headers=hx).json() == []
    # s1 meeting untouched
    assert client.get("/secretary/meetings", headers=world["secretary"].headers).json()[0]["status"] == "upcoming"


def test_invited_count_ignores_ended_and_dedupes(client, world, db):
    # tenant also owns A-101 (duplicate user), an ended membership is ignored
    old = models.User(id=uuid.uuid4(), email="gone@example.com", full_name="gone")
    db.add(old)
    db.flush()
    db.add_all([
        models.FlatMembership(flat_id=world["a101"], user_id=world["tenant"].id, kind="owner",
                              is_resident=True, start_date=date.today() - timedelta(days=1)),
        models.FlatMembership(flat_id=world["a101"], user_id=old.id, kind="owner", is_resident=False,
                              start_date=date.today() - timedelta(days=20),
                              end_date=date.today() - timedelta(days=2)),
    ])
    db.commit()
    assert _create(client, world).json()["invited_count"] == 3
    assert _create(client, world, audience="owners").json()["invited_count"] == 3
    lst = client.get("/secretary/meetings", headers=world["secretary"].headers).json()
    assert {m["invited_count"] for m in lst} == {3}
    # tenant is now an owner too, so sees owners-only meetings
    assert len(_mine(client, world, "tenant")) == 2
