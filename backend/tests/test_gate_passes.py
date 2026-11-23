import threading
import uuid
from datetime import date, timedelta

import models

ALPHA = set("ABCDEFGHJKMNPQRSTUVWXYZ23456789")


def body(**kw):
    d = {
        "visitor_name": "  Ravi Kumar ",
        "visitor_phone": "+91 98765-43210",
        "visitor_email": "Ravi@Example.com",
        "visit_date": date.today().isoformat(),
    }
    d.update(kw)
    return d


def mk(client, who, **kw):
    r = client.post("/passes", json=body(**kw), headers=who.headers)
    assert r.status_code == 201, r.text
    return r.json()


def checkin(client, world, pid, who="guard"):
    return client.post(f"/guard/passes/{pid}/check-in", headers=world[who].headers)


def verify(client, world, code, who="guard"):
    return client.post("/guard/passes/verify", json={"code": code}, headers=world[who].headers)


def test_create_normalises(client, world):
    p = mk(client, world["owner"], vehicle_number="ka01ab1234", valid_days=3)
    assert p["visitor_name"] == "Ravi Kumar"
    assert p["visitor_phone"] == "+919876543210"
    assert p["visitor_email"] == "ravi@example.com"
    assert p["vehicle_number"] == "KA01AB1234"
    assert p["status"] == "active" and p["flat_number"] == "A-101"
    assert p["valid_until"] == (date.today() + timedelta(days=2)).isoformat()
    assert len(p["pass_code"]) == 8 and set(p["pass_code"]) <= ALPHA


def test_validation(client, world):
    h = world["owner"].headers

    def code(**kw):
        r = client.post("/passes", json=body(**kw), headers=h)
        return r.status_code, r.json().get("detail")

    assert code(visitor_name="A")[0] == 422
    assert code(visitor_phone="12345") == (422, "Please enter a valid phone number.")
    assert code(visitor_phone="1234567890123456") == (422, "Please enter a valid phone number.")
    assert code(visitor_email="nope") == (422, "Please enter a valid email address.")
    assert code(visit_date=(date.today() - timedelta(days=1)).isoformat())[0] == 422
    assert code(visit_date=(date.today() + timedelta(days=31)).isoformat())[0] == 422
    assert code(visit_date=(date.today() + timedelta(days=30)).isoformat())[0] == 201
    assert code(valid_days=0)[0] == 422
    assert code(valid_days=8)[0] == 422


def test_only_residents_create(client, world):
    for n in ("stranger", "guard", "landlord"):
        r = client.post("/passes", json=body(), headers=world[n].headers)
        assert r.status_code == 403, n
        assert r.json()["detail"] == "Only residents can create gate passes."


def test_list_scope(client, world):
    mk(client, world["tenant"])
    assert len(client.get("/passes", headers=world["tenant"].headers).json()) == 1
    assert client.get("/passes", headers=world["owner"].headers).json() == []
    mk(client, world["owner"])
    assert len(client.get("/passes", headers=world["owner"].headers).json()) == 1
    assert client.get("/passes", headers=world["stranger"].headers).json() == []


def test_list_shared_by_flat(client, db, world):
    u = models.User(id=uuid.uuid4(), email="co@example.com", full_name="co")
    db.add(u)
    db.flush()
    db.add(models.FlatMembership(
        flat_id=world["a101"], user_id=u.id, kind="tenant", is_resident=True,
        start_date=date.today() - timedelta(days=1)))
    db.commit()
    p = mk(client, world["owner"])
    h = {"x-test-sub": str(u.id), "x-test-email": "co@example.com"}
    assert len(client.get("/passes", headers=h).json()) == 1
    # any resident of the flat may cancel
    assert client.post(f"/passes/{p['id']}/cancel", headers=h).status_code == 200


def test_cancel_rules(client, world):
    p = mk(client, world["owner"])
    assert client.post(f"/passes/{p['id']}/cancel", headers=world["tenant"].headers).status_code == 404
    assert client.post(f"/passes/{p['id']}/cancel", headers=world["stranger"].headers).status_code == 404
    r = client.post(f"/passes/{p['id']}/cancel", headers=world["owner"].headers)
    assert r.status_code == 200 and r.json()["status"] == "cancelled"
    p2 = mk(client, world["owner"])
    assert checkin(client, world, p2["id"]).status_code == 200
    r = client.post(f"/passes/{p2['id']}/cancel", headers=world["owner"].headers)
    assert r.status_code == 409 and r.json()["detail"] == "This pass was already used."


def test_verify_states(client, db, world):
    p = mk(client, world["owner"])
    r = verify(client, world, " " + p["pass_code"].lower() + " ")
    assert r.status_code == 200
    j = r.json()
    assert j["valid"] is True and j["reason"] is None
    assert j["pass"]["owner_names"] == ["owner"] and j["pass"]["flat_number"] == "A-101"

    # expired
    row = db.get(models.GatePass, p["id"])
    row.visit_date = date.today() - timedelta(days=3)
    row.valid_until_date = date.today() - timedelta(days=1)
    db.commit()
    j = verify(client, world, p["pass_code"]).json()
    assert j["valid"] is False and j["reason"] == "This pass has expired."
    assert client.get("/passes", headers=world["owner"].headers).json()[0]["status"] == "expired"
    assert checkin(client, world, p["id"]).status_code == 409

    # future
    f = mk(client, world["owner"], visit_date=(date.today() + timedelta(days=2)).isoformat())
    j = verify(client, world, f["pass_code"]).json()
    assert j["valid"] is False and j["reason"] == f"This pass is for {f['visit_date']}."
    assert checkin(client, world, f["id"]).status_code == 409

    # used
    u = mk(client, world["owner"])
    checkin(client, world, u["id"])
    assert verify(client, world, u["pass_code"]).json()["reason"] == "This pass was already used."

    # cancelled
    c = mk(client, world["owner"])
    client.post(f"/passes/{c['id']}/cancel", headers=world["owner"].headers)
    assert verify(client, world, c["pass_code"]).json()["reason"] == "This pass was cancelled."
    r = checkin(client, world, c["id"])
    assert r.status_code == 409 and r.json()["detail"] == "This pass was cancelled."


def test_verify_unknown_and_other_society(client, db, world):
    r = verify(client, world, "ZZZZZZZZ")
    assert r.status_code == 404
    assert r.json()["detail"] == "We could not find that pass. Please check the code."
    p = mk(client, world["owner"])
    row = db.get(models.GatePass, p["id"])
    row.society_id = world["s2"]
    db.commit()
    assert verify(client, world, p["pass_code"]).status_code == 404
    assert checkin(client, world, p["id"]).status_code == 404


def test_check_in_creates_guest(client, db, world):
    p = mk(client, world["owner"])
    r = checkin(client, world, p["id"])
    assert r.status_code == 200
    assert r.json()["status"] == "used" and r.json()["used_at"]
    row = db.get(models.GatePass, p["id"])
    assert row.guest_request_id
    gl = client.get("/guard/guests", headers=world["guard"].headers).json()
    g = [x for x in gl if x["id"] == row.guest_request_id][0]
    assert g["status"] == "checked_in" and g["guest_name"] == "Ravi Kumar" and g["flat_number"] == "A-101"
    assert g["checked_in_at"]
    hist = client.get("/guests/history", headers=world["owner"].headers).json()
    assert any(x["id"] == g["id"] for x in hist)
    assert checkin(client, world, p["id"]).status_code == 409


def test_check_in_race(client, world):
    p = mk(client, world["owner"])
    codes = []

    def go():
        codes.append(checkin(client, world, p["id"]).status_code)

    ts = [threading.Thread(target=go) for _ in range(2)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert sorted(codes) == [200, 409]


def test_guard_only(client, world):
    p = mk(client, world["owner"])
    for n in ("owner", "stranger", "secretary"):
        h = world[n].headers
        assert client.post("/guard/passes/verify", json={"code": p["pass_code"]}, headers=h).status_code == 403
        assert client.post(f"/guard/passes/{p['id']}/check-in", headers=h).status_code == 403
        assert client.get("/guard/passes/today", headers=h).status_code == 403


def test_codes_unique(client, world):
    codes = {mk(client, world["owner"])["pass_code"] for _ in range(12)}
    assert len(codes) == 12


def test_today_hides_code(client, world):
    a = mk(client, world["owner"])
    mk(client, world["owner"], visit_date=(date.today() + timedelta(days=3)).isoformat())
    c = mk(client, world["owner"])
    client.post(f"/passes/{c['id']}/cancel", headers=world["owner"].headers)
    rows = client.get("/guard/passes/today", headers=world["guard"].headers).json()
    assert [r["id"] for r in rows] == [a["id"]]
    assert "pass_code" not in rows[0] and rows[0]["flat_number"] == "A-101"
