import threading
import uuid
from datetime import datetime, timedelta, timezone

import models


def future(days=5):
    return (datetime.now(timezone.utc) + timedelta(days=days)).isoformat()


def mk(client, world, **kw):
    body = {"title": "Paint colour", "options": ["Blue", "Green"], "closes_at": future()}
    body.update(kw)
    return client.post("/secretary/polls", headers=world["secretary"].headers, json=body)


def vote(client, who, poll, idx=0):
    return client.post(
        f"/polls/{poll['id']}/vote", headers=who.headers,
        json={"option_id": poll["options"][idx]["id"]},
    )


def listing(client, who):
    return client.get("/polls", headers=who.headers).json()


def test_admin_creates(client, world):
    r = mk(client, world, title="  Lift repair ", description="Cost 5L", audience="owners")
    assert r.status_code == 201
    p = r.json()
    assert p["title"] == "Lift repair" and p["audience"] == "owners" and p["status"] == "open"
    assert [o["text"] for o in p["options"]] == ["Blue", "Green"]
    assert all(o["votes"] == 0 for o in p["options"])
    assert p["can_vote"] is False and p["eligible"] is False and p["has_voted"] is False
    assert p["closes_at"].endswith("+00:00") or "+" in p["closes_at"]
    assert len(client.get("/secretary/polls", headers=world["secretary"].headers).json()) == 1


def test_everyone_audience_all_residents_vote(client, world):
    p = mk(client, world).json()
    for who in ("owner", "tenant", "landlord"):
        r = vote(client, world[who], p)
        assert r.status_code == 200, who
        assert r.json()["has_voted"] is True and r.json()["can_vote"] is False


def test_owners_audience(client, world):
    p = mk(client, world, audience="owners").json()
    r = vote(client, world["tenant"], p)
    assert r.status_code == 403 and r.json()["detail"] == "Only owners can vote in this poll."
    assert vote(client, world["owner"], p).status_code == 200
    assert vote(client, world["landlord"], p).status_code == 200
    seen = listing(client, world["tenant"])[0]
    assert seen["eligible"] is False and seen["can_vote"] is False
    assert all(o["votes"] is None for o in seen["options"])


def test_stranger_guard_cannot_vote(client, world):
    p = mk(client, world).json()
    for who in ("stranger", "guard"):
        r = vote(client, world[who], p)
        assert r.status_code == 403
        assert r.json()["detail"] == "Only residents of this society can vote."
    assert listing(client, world["stranger"]) == []


def test_one_vote_per_person(client, world):
    p = mk(client, world).json()
    assert vote(client, world["owner"], p, 0).status_code == 200
    r = vote(client, world["owner"], p, 1)
    assert r.status_code == 409 and r.json()["detail"] == "You have already voted in this poll."


def test_vote_race(client, world, db):
    p = mk(client, world).json()
    codes = []
    barrier = threading.Barrier(2)

    def go(idx):
        barrier.wait()
        codes.append(vote(client, world["owner"], p, idx).status_code)

    ts = [threading.Thread(target=go, args=(i,)) for i in (0, 1)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert sorted(codes) == [200, 409]
    assert db.query(models.PollVote).count() == 1


def test_results_hidden_until_voted(client, world):
    p = mk(client, world).json()
    before = listing(client, world["owner"])[0]
    assert before["can_vote"] is True and before["eligible"] is True
    assert all(o["votes"] is None for o in before["options"])
    assert before["my_option_id"] is None
    r = vote(client, world["owner"], p, 1).json()
    assert [o["votes"] for o in r["options"]] == [0, 1]
    assert r["my_option_id"] == p["options"][1]["id"]
    # others still blind
    assert all(o["votes"] is None for o in listing(client, world["tenant"])[0]["options"])


def test_counts_and_totals(client, world):
    p = mk(client, world).json()
    vote(client, world["owner"], p, 0)
    vote(client, world["tenant"], p, 0)
    r = vote(client, world["landlord"], p, 1).json()
    assert [o["votes"] for o in r["options"]] == [2, 1]
    assert r["total_votes"] == 3 and r["eligible_count"] == 3
    adm = client.get("/secretary/polls", headers=world["secretary"].headers).json()[0]
    assert [o["votes"] for o in adm["options"]] == [2, 1] and adm["total_votes"] == 3


def test_closed_early_rejects_and_reveals(client, world):
    p = mk(client, world).json()
    vote(client, world["owner"], p, 0)
    c = client.post(f"/secretary/polls/{p['id']}/close", headers=world["secretary"].headers)
    assert c.status_code == 200 and c.json()["status"] == "closed"
    first = c.json()["closed_at"]
    again = client.post(f"/secretary/polls/{p['id']}/close", headers=world["secretary"].headers)
    assert again.json()["closed_at"] == first
    r = vote(client, world["tenant"], p)
    assert r.status_code == 409 and r.json()["detail"] == "This poll has closed."
    seen = listing(client, world["tenant"])[0]
    assert seen["status"] == "closed" and seen["can_vote"] is False
    assert [o["votes"] for o in seen["options"]] == [1, 0]


def test_expired_by_time(client, world, db):
    p = mk(client, world).json()
    db.query(models.Poll).update({"closes_at": datetime.now(timezone.utc) - timedelta(hours=1)})
    db.commit()
    assert vote(client, world["owner"], p).status_code == 409
    seen = listing(client, world["owner"])[0]
    assert seen["status"] == "closed" and seen["options"][0]["votes"] == 0


def test_option_of_other_poll(client, world):
    p1 = mk(client, world).json()
    p2 = mk(client, world, title="Other").json()
    r = client.post(
        f"/polls/{p1['id']}/vote", headers=world["owner"].headers,
        json={"option_id": p2["options"][0]["id"]},
    )
    assert r.status_code == 422
    assert client.post(
        f"/polls/{p1['id']}/vote", headers=world["owner"].headers, json={"option_id": 999999}
    ).status_code == 422


def test_creation_validation(client, world):
    bad = [
        {"options": ["Only"]},
        {"options": [str(i) for i in range(7)]},
        {"options": ["Yes", " yes "]},
        {"options": ["Yes", "  "]},
        {"title": "   "},
        {"title": "x" * 151},
        {"closes_at": future(-1)},
        {"closes_at": future(91)},
        {"audience": "nobody"},
    ]
    for b in bad:
        assert mk(client, world, **b).status_code == 422, b
    assert mk(client, world, options=[str(i) for i in range(6)], closes_at=future(89)).status_code == 201


def test_non_admin_forbidden(client, world):
    body = {"title": "t", "options": ["a", "b"], "closes_at": future()}
    p = mk(client, world).json()
    for who in ("owner", "tenant", "guard", "stranger"):
        h = world[who].headers
        assert client.post("/secretary/polls", headers=h, json=body).status_code == 403
        assert client.get("/secretary/polls", headers=h).status_code == 403
        assert client.post(f"/secretary/polls/{p['id']}/close", headers=h).status_code == 403


def test_cross_society(client, world):
    p = mk(client, world).json()
    h2 = world["secretary2"].headers
    assert client.post(f"/secretary/polls/{p['id']}/close", headers=h2).status_code == 404
    assert client.get("/secretary/polls", headers=h2).json() == []
    assert client.get("/polls", headers=h2).json() == []


def test_cross_society_resident(client, world, db):
    p = mk(client, world).json()
    u = models.User(id=uuid.uuid4(), email="x2@example.com", full_name="x2")
    db.add(u)
    db.flush()
    db.add(models.FlatMembership(
        flat_id=world["x1"], user_id=u.id, kind="owner", is_resident=True,
        start_date=datetime.now().date() - timedelta(days=1),
    ))
    db.commit()
    h = {"x-test-sub": str(u.id), "x-test-email": u.email}
    assert client.get("/polls", headers=h).json() == []
    r = client.post(f"/polls/{p['id']}/vote", headers=h, json={"option_id": p["options"][0]["id"]})
    assert r.status_code in (403, 404)
    assert db.query(models.PollVote).count() == 0


def test_eligible_count(client, world):
    ev = mk(client, world).json()
    ow = mk(client, world, audience="owners", title="Owners").json()
    assert ev["eligible_count"] == 3 and ow["eligible_count"] == 2
    by = {p["id"]: p for p in listing(client, world["owner"])}
    assert by[ev["id"]]["eligible_count"] == 3 and by[ow["id"]]["eligible_count"] == 2


def test_ordering_open_before_closed(client, world, db):
    a = mk(client, world, title="late", closes_at=future(10)).json()
    b = mk(client, world, title="soon", closes_at=future(2)).json()
    c = mk(client, world, title="closed1").json()
    d = mk(client, world, title="closed2").json()
    old = mk(client, world, title="ancient").json()
    now = datetime.now(timezone.utc)
    for pid, delta in ((c["id"], 5), (d["id"], 2), (old["id"], 70)):
        poll = db.get(models.Poll, pid)
        poll.closes_at = now - timedelta(days=delta)
    db.commit()
    titles = [p["title"] for p in listing(client, world["owner"])]
    assert titles == ["soon", "late", "closed2", "closed1"]
