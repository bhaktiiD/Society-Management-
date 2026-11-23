import threading
from datetime import date, timedelta

from test_bookings import DAY, book, hall

SEC = "/secretary/bookings"


def req(client, world, who="owner", **kw):
    aid = hall(client, world["owner"])
    r = book(client, world[who], aid, **kw)
    assert r.status_code == 201, r.text
    return aid, r.json()["id"]


def act(client, world, bid, action, who="secretary", **json):
    return client.post(f"{SEC}/{bid}/{action}", headers=world[who].headers, json=json or None)


def mine(client, world, who):
    return client.get("/bookings/mine", headers=world[who].headers).json()


def test_approve_happy_path(client, world):
    _, bid = req(client, world, purpose="Party")
    r = act(client, world, bid, "approve")
    assert r.status_code == 200 and r.json()["status"] == "confirmed"
    m = mine(client, world, "owner")[0]
    assert m["status"] == "confirmed" and m["decided_at"] and m["admin_note"] is None
    assert act(client, world, bid, "approve").status_code == 409


def test_two_requests_approve_first_then_reschedule(client, world):
    aid, b1 = req(client, world, "owner")
    _, b2 = req(client, world, "tenant")
    assert act(client, world, b1, "approve").status_code == 200
    r = act(client, world, b2, "approve")
    assert r.status_code == 409
    assert "overlaps another confirmed booking" in r.json()["detail"]
    assert mine(client, world, "tenant")[0]["status"] == "pending"
    r = act(client, world, b2, "reschedule", note="Try next week")
    assert r.status_code == 200 and r.json()["status"] == "reschedule"
    m = mine(client, world, "tenant")[0]
    assert m["status"] == "reschedule" and m["admin_note"] == "Try next week"
    assert act(client, world, b2, "reschedule").status_code == 409


def test_decline_requires_reason(client, world):
    _, bid = req(client, world)
    assert act(client, world, bid, "decline").status_code == 422
    assert act(client, world, bid, "decline", reason="  no ").status_code == 422
    assert act(client, world, bid, "decline", reason="x" * 301).status_code == 422
    r = act(client, world, bid, "decline", reason="  Hall under repair  ")
    assert r.status_code == 200 and r.json()["status"] == "declined"
    m = mine(client, world, "owner")[0]
    assert m["status"] == "declined" and m["admin_note"] == "Hall under repair"
    assert act(client, world, bid, "decline", reason="Another reason").status_code == 409
    # declined bookings are not cancellable
    r = client.delete(f"/bookings/{bid}", headers=world["owner"].headers)
    assert r.json()["status"] == "declined"


def test_other_society_admin_gets_404(client, world):
    _, bid = req(client, world)
    for action, js in (("approve", {}), ("reschedule", {}), ("decline", {"reason": "Not allowed"})):
        assert act(client, world, bid, action, who="secretary2", **js).status_code == 404
    assert act(client, world, 99999, "approve").status_code == 404


def test_resident_cannot_use_admin_endpoints(client, world):
    _, bid = req(client, world)
    for action, js in (("approve", {}), ("reschedule", {}), ("decline", {"reason": "Not allowed"})):
        assert act(client, world, bid, action, who="owner", **js).status_code == 403
    assert client.get(SEC, headers=world["owner"].headers).status_code == 403
    assert mine(client, world, "owner")[0]["status"] == "pending"


def test_resident_cancels_pending_and_reschedule(client, world):
    _, bid = req(client, world)
    r = client.delete(f"/bookings/{bid}", headers=world["owner"].headers)
    assert r.status_code == 200 and r.json()["status"] == "cancelled"
    _, b2 = req(client, world)
    act(client, world, b2, "reschedule")
    r = client.delete(f"/bookings/{b2}", headers=world["owner"].headers)
    assert r.json()["status"] == "cancelled"


def test_replaces_booking_cancels_old_reschedule(client, world):
    aid, old = req(client, world)
    act(client, world, old, "reschedule")
    other = DAY + timedelta(days=2)
    r = book(client, world["owner"], aid, d=other, replaces_booking_id=old)
    assert r.status_code == 201
    by_id = {b["id"]: b for b in mine(client, world, "owner")}
    assert by_id[old]["status"] == "cancelled" and by_id[r.json()["id"]]["status"] == "pending"
    # someone else's / non-reschedule bookings are ignored safely
    _, tb = req(client, world, "tenant")
    r = book(client, world["owner"], aid, d=other + timedelta(days=1), replaces_booking_id=tb)
    assert r.status_code == 201
    assert mine(client, world, "tenant")[0]["status"] == "pending"
    r = book(client, world["owner"], aid, d=other + timedelta(days=2), replaces_booking_id=99999)
    assert r.status_code == 201


def test_slot_taken_flag_and_extra_fields(client, world, db):
    import models

    db.get(models.User, world["tenant"].id).phone = "9999900000"
    db.commit()
    _, b1 = req(client, world, "owner", purpose="Party")
    _, b2 = req(client, world, "tenant")
    rows = {r["id"]: r for r in client.get(SEC, headers=world["secretary"].headers).json()}
    assert not rows[b1]["slot_taken"] and not rows[b2]["slot_taken"]
    assert rows[b1]["booker_kind"] == "owner" and rows[b2]["booker_kind"] == "tenant"
    assert rows[b1]["booker_phone"] is None and rows[b2]["booker_phone"] == "9999900000"
    for k in ("booker_name", "flat_number", "purpose", "slot", "date", "status",
              "admin_note", "decided_at", "created_at", "start_time", "end_time", "time_label"):
        assert k in rows[b1]
    act(client, world, b1, "approve")
    rows = {r["id"]: r for r in client.get(SEC, headers=world["secretary"].headers).json()}
    assert rows[b2]["slot_taken"] is True and rows[b1]["slot_taken"] is False


def test_pending_listed_first(client, world):
    aid, b1 = req(client, world, "owner", d=DAY + timedelta(days=5))
    act(client, world, b1, "approve")
    _, b2 = req(client, world, "tenant", d=DAY)
    rows = client.get(SEC, headers=world["secretary"].headers).json()
    assert [r["id"] for r in rows] == [b2, b1]


def test_duplicate_and_confirmed_precheck(client, world):
    aid, b1 = req(client, world, "owner")
    r = book(client, world["owner"], aid)
    assert r.status_code == 409 and r.json()["detail"] == "You already have a request for that time."
    act(client, world, b1, "approve")
    r = book(client, world["owner"], aid)
    assert r.status_code == 409  # confirmed overlap check wins
    assert r.json()["detail"] == "That time is already booked. Please pick another time."
    r = book(client, world["tenant"], aid)
    assert r.status_code == 409
    assert r.json()["detail"] == "That time is already booked. Please pick another time."


def test_race_two_approvals_one_wins(client, world):
    _, b1 = req(client, world, "owner")
    _, b2 = req(client, world, "tenant")
    codes = []

    def go(bid):
        codes.append(act(client, world, bid, "approve").status_code)

    ts = [threading.Thread(target=go, args=(b,)) for b in (b1, b2)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert sorted(codes) == [200, 409]
