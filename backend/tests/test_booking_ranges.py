import threading
from datetime import date, datetime, timedelta

import pytest

from routers.bookings import slot_label_for, time_label
from test_bookings import DAY, approve, book, hall

SEC = "/secretary/bookings"


def ok(r, code=201):
    assert r.status_code == code, r.text
    return r.json()


def test_label_helpers():
    assert slot_label_for(8) == "morning" and slot_label_for(12) == "morning"
    assert slot_label_for(13) == "evening" and slot_label_for(21) == "evening"
    d = datetime(2026, 1, 1)
    assert time_label(d.replace(hour=21), d.replace(hour=22)) == "9 PM - 10 PM"
    assert time_label(d.replace(hour=9, minute=30), d.replace(hour=12)) == "9:30 AM - 12 PM"


def test_valid_evening_range_pending_then_approvable(client, world):
    aid = hall(client, world["owner"])
    b = ok(book(client, world["owner"], aid, start="21:00", end="22:00"))
    assert b["status"] == "pending"
    assert (b["start_time"], b["end_time"], b["time_label"]) == ("21:00", "22:00", "9 PM - 10 PM")
    assert b["slot"] == "evening"
    assert approve(client, world, b["id"]).status_code == 200
    m = client.get("/bookings/mine", headers=world["owner"].headers).json()[0]
    assert m["status"] == "confirmed" and m["time_label"] == "9 PM - 10 PM"


def test_overlap_blocked_on_approve(client, world):
    aid = hall(client, world["owner"])
    b1 = ok(book(client, world["owner"], aid, start="09:00", end="11:00"))["id"]
    b2 = ok(book(client, world["tenant"], aid, start="10:00", end="12:00"))["id"]
    assert approve(client, world, b1).status_code == 200
    r = approve(client, world, b2)
    assert r.status_code == 409
    assert r.json()["detail"] == (
        "This time overlaps another confirmed booking. Ask the resident to pick a new time."
    )
    m = client.get("/bookings/mine", headers=world["tenant"].headers).json()[0]
    assert m["status"] == "pending"


def test_race_overlapping_approvals_one_wins(client, world):
    aid = hall(client, world["owner"])
    b1 = ok(book(client, world["owner"], aid, start="09:00", end="11:00"))["id"]
    b2 = ok(book(client, world["tenant"], aid, start="10:00", end="12:00"))["id"]
    codes = []
    ts = [threading.Thread(target=lambda b=b: codes.append(approve(client, world, b).status_code))
          for b in (b1, b2)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert sorted(codes) == [200, 409]


def test_db_constraint_blocks_overlap(world, db):
    import models
    from sqlalchemy.exc import IntegrityError

    amenity = models.Amenity(society_id=world["s1"], name="Hall2")
    db.add(amenity)
    db.flush()

    def mk(h1, h2):
        return models.Booking(
            amenity_id=amenity.id, flat_id=world["a101"], booked_by=world["owner"].id,
            booking_date=DAY, slot="morning", status="confirmed",
            start_at=datetime.combine(DAY, datetime.min.time()).replace(hour=h1),
            end_at=datetime.combine(DAY, datetime.min.time()).replace(hour=h2),
        )

    db.add(mk(9, 11))
    db.add(mk(11, 12))  # adjacent: fine
    db.commit()
    db.add(mk(10, 13))
    with pytest.raises(IntegrityError):
        db.commit()
    db.rollback()


def test_adjacent_ranges_both_approvable(client, world):
    aid = hall(client, world["owner"])
    b1 = ok(book(client, world["owner"], aid, start="21:00", end="22:00"))["id"]
    b2 = ok(book(client, world["tenant"], aid, start="20:00", end="21:00"))["id"]
    assert approve(client, world, b1).status_code == 200
    assert approve(client, world, b2).status_code == 200


def test_availability_lists_confirmed_busy_sorted(client, world):
    aid = hall(client, world["owner"])
    late = ok(book(client, world["owner"], aid, start="18:00", end="20:00"))["id"]
    early = ok(book(client, world["tenant"], aid, start="09:30", end="12:00"))["id"]
    ok(book(client, world["tenant"], aid, start="14:00", end="16:00"))  # stays pending
    approve(client, world, late)
    approve(client, world, early)
    av = client.get(f"/amenities/{aid}/availability?days=5", headers=world["owner"].headers).json()
    assert len(av) == 5
    row = next(r for r in av if r["date"] == DAY.isoformat())
    assert row["busy"] == [{"start": "09:30", "end": "12:00"}, {"start": "18:00", "end": "20:00"}]
    assert row["open"] == "08:00" and row["close"] == "22:00"
    assert all(r["busy"] == [] for r in av if r["date"] != DAY.isoformat())
    assert client.get(f"/amenities/{aid}/availability?days=0", headers=world["owner"].headers).status_code == 422


@pytest.mark.parametrize("start,end,msg", [
    ("07:00", "09:00", "The hall is open from 8 AM to 10 PM."),
    ("20:00", "23:00", "The hall is open from 8 AM to 10 PM."),
    ("09:20", "11:00", "Please choose times on the hour or half hour."),
    ("09:00", "10:00", None),
    ("09:00", "09:30", "Bookings must be at least 1 hour."),
    ("08:00", "17:00", "Bookings can be at most 8 hours."),
    ("11:00", "10:00", "Bookings must be at least 1 hour."),
    ("11:00", "11:00", "Bookings must be at least 1 hour."),
])
def test_validation(client, world, start, end, msg):
    aid = hall(client, world["owner"])
    r = book(client, world["owner"], aid, start=start, end=end)
    if msg is None:
        assert r.status_code == 201
    else:
        assert r.status_code == 422 and r.json()["detail"] == msg


@pytest.mark.parametrize("start", ["9am", "9:00", "25:00", "09:60", "", "0900"])
def test_bad_time_format(client, world, start):
    aid = hall(client, world["owner"])
    assert book(client, world["owner"], aid, start=start, end="12:00").status_code == 422
    assert book(client, world["owner"], aid, start="09:00", end=start).status_code == 422


def test_past_start_today_and_date_limits(client, world):
    aid = hall(client, world["owner"])
    now = datetime.now()
    if now.hour >= 9:
        r = book(client, world["owner"], aid, d=date.today(), start="08:00", end="09:00")
        assert r.status_code == 422
        assert r.json()["detail"] == "Please pick a start time in the future."
    assert book(client, world["owner"], aid, d=date.today() + timedelta(days=91)).status_code == 422
    assert book(client, world["owner"], aid, d=date.today() + timedelta(days=90)).status_code == 201


def test_resident_precheck_on_confirmed_overlap(client, world):
    aid = hall(client, world["owner"])
    b = ok(book(client, world["owner"], aid, start="10:00", end="12:00"))["id"]
    approve(client, world, b)
    r = book(client, world["tenant"], aid, start="11:00", end="13:00")
    assert r.status_code == 409
    assert r.json()["detail"] == "That time is already booked. Please pick another time."
    assert book(client, world["tenant"], aid, start="12:00", end="13:00").status_code == 201


def test_duplicate_overlapping_own_request(client, world):
    aid = hall(client, world["owner"])
    ok(book(client, world["owner"], aid, start="10:00", end="12:00"))
    r = book(client, world["owner"], aid, start="11:00", end="13:00")
    assert r.status_code == 409 and r.json()["detail"] == "You already have a request for that time."
    assert book(client, world["tenant"], aid, start="11:00", end="13:00").status_code == 201


def test_slot_taken_flag_overlap(client, world):
    aid = hall(client, world["owner"])
    b1 = ok(book(client, world["owner"], aid, start="10:00", end="12:00"))["id"]
    b2 = ok(book(client, world["tenant"], aid, start="11:00", end="13:00"))["id"]
    b3 = ok(book(client, world["tenant"], aid, start="13:00", end="14:00"))["id"]
    approve(client, world, b1)
    rows = {r["id"]: r for r in client.get(SEC, headers=world["secretary"].headers).json()}
    assert rows[b2]["slot_taken"] is True
    assert rows[b3]["slot_taken"] is False
    assert rows[b1]["slot_taken"] is False
    assert rows[b1]["time_label"] == "10 AM - 12 PM"
