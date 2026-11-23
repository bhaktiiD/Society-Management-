import threading
from datetime import date, timedelta

DAY = date.today() + timedelta(days=3)


def hall(client, who):
    r = client.get("/amenities", headers=who.headers)
    assert r.status_code == 200
    return r.json()[0]["id"]


def book(client, who, aid, d=DAY, start="10:00", end="12:00", **kw):
    return client.post(
        "/bookings", headers=who.headers,
        json={"amenity_id": aid, "date": d.isoformat(), "start_time": start, "end_time": end, **kw},
    )


def approve(client, world, bid):
    return client.post(f"/secretary/bookings/{bid}/approve", headers=world["secretary"].headers)


def test_default_amenity_created_once(client, world):
    a = client.get("/amenities", headers=world["owner"].headers).json()
    b = client.get("/amenities", headers=world["secretary"].headers).json()
    c = client.get("/amenities", headers=world["guard"].headers).json()
    assert len(a) == 1 and a[0]["name"] == "Community Hall"
    assert a == b == c
    assert client.get("/amenities", headers=world["stranger"].headers).status_code == 403


def test_availability_marks_booked(client, world):
    aid = hall(client, world["owner"])
    bid = book(client, world["owner"], aid)
    assert bid.status_code == 201 and bid.json()["status"] == "pending"
    av = client.get(f"/amenities/{aid}/availability?days=5", headers=world["tenant"].headers).json()
    assert all(r["busy"] == [] for r in av)  # pending does not block
    assert approve(client, world, bid.json()["id"]).status_code == 200
    av =client.get(f"/amenities/{aid}/availability?days=5", headers=world["tenant"].headers).json()
    assert len(av) == 5
    row = next(r for r in av if r["date"] == DAY.isoformat())
    assert row == {
        "date": DAY.isoformat(), "busy": [{"start": "10:00", "end": "12:00"}],
        "open": "08:00", "close": "22:00",
    }
    assert client.get(f"/amenities/{aid}/availability?days=91", headers=world["owner"].headers).status_code == 422


def test_double_booking_and_independent_slots(client, world):
    aid = hall(client, world["owner"])
    r = book(client, world["owner"], aid, purpose="Party")
    assert r.status_code == 201
    assert approve(client, world, r.json()["id"]).status_code == 200
    r = book(client, world["tenant"], aid)
    assert r.status_code == 409
    assert r.json()["detail"] == "That time is already booked. Please pick another time."
    assert book(client, world["tenant"], aid, start="14:00", end="16:00").status_code == 201


def test_concurrent_same_slot(client, world):
    # Requests only queue up as pending; both succeed.
    aid = hall(client, world["owner"])
    codes = []

    def go(who):
        codes.append(book(client, who, aid).status_code)

    ts = [threading.Thread(target=go, args=(world[n],)) for n in ("owner", "tenant")]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert codes == [201, 201]


def test_who_can_book(client, world):
    aid = hall(client, world["owner"])
    assert book(client, world["landlord"], aid).status_code == 403
    assert book(client, world["guard"], aid).status_code == 403
    assert book(client, world["stranger"], aid).status_code == 403
    assert book(client, world["tenant"], aid, flat_id=world["a101"]).status_code == 404
    r = book(client, world["tenant"], aid, flat_id=world["b202"])
    assert r.status_code == 201 and r.json()["flat_number"] == "B-202"


def test_date_and_time_validation(client, world):
    aid = hall(client, world["owner"])
    assert book(client, world["owner"], aid, d=date.today() - timedelta(days=1)).status_code == 422
    assert book(client, world["owner"], aid, d=date.today() + timedelta(days=91)).status_code == 422
    assert book(client, world["owner"], aid, start="7:00").status_code == 422
    from datetime import datetime
    ok = datetime.now().hour < 20
    r = book(client, world["owner"], aid, d=date.today(), start="21:00", end="22:00")
    assert r.status_code == (201 if ok else 422)


def test_cancel_own_frees_slot(client, world):
    aid = hall(client, world["owner"])
    bid = book(client, world["owner"], aid).json()["id"]
    assert client.delete(f"/bookings/{bid}", headers=world["tenant"].headers).status_code == 404
    assert client.delete(f"/bookings/{bid}", headers=world["owner"].headers).json()["status"] == "cancelled"
    assert client.delete(f"/bookings/{bid}", headers=world["owner"].headers).status_code == 200
    assert client.delete("/bookings/99999", headers=world["owner"].headers).status_code == 404
    assert book(client, world["tenant"], aid).status_code == 201
    mine = client.get("/bookings/mine", headers=world["owner"].headers).json()
    assert len(mine) == 1 and mine[0]["status"] == "cancelled"
    assert mine[0]["amenity_name"] == "Community Hall" and mine[0]["flat_number"] == "A-101"


def test_admin_lists_and_cancels(client, world):
    aid = hall(client, world["owner"])
    bid = book(client, world["owner"], aid, purpose="Birthday").json()["id"]
    rows = client.get("/secretary/bookings?upcoming=true", headers=world["secretary"].headers).json()
    assert len(rows) == 1
    assert rows[0]["flat_number"] == "A-101" and rows[0]["booker_name"] == "owner"
    assert rows[0]["status"] == "pending"
    assert client.get("/secretary/bookings", headers=world["owner"].headers).status_code == 403
    assert approve(client, world, bid).status_code == 200
    r = client.post(f"/secretary/bookings/{bid}/cancel", headers=world["secretary"].headers)
    assert r.status_code == 200 and r.json()["status"] == "cancelled"
    assert client.post(f"/secretary/bookings/{bid}/cancel", headers=world["secretary"].headers).status_code == 200
    assert book(client, world["tenant"], aid).status_code == 201


def test_cross_society_isolation(client, world, db):
    aid = hall(client, world["owner"])
    bid = book(client, world["owner"], aid).json()["id"]
    s2 = world["secretary2"]
    assert client.get("/secretary/bookings", headers=s2.headers).json() == []
    assert client.post(f"/secretary/bookings/{bid}/cancel", headers=s2.headers).status_code == 404
    assert client.get(f"/amenities/{aid}/availability", headers=s2.headers).status_code == 404
