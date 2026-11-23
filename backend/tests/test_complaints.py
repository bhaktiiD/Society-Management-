import pytest

BODY = {"category": "plumbing", "title": "Leaking tap", "description": "Kitchen tap drips."}


def _create(client, who, **over):
    return client.post("/complaints", json={**BODY, **over}, headers=who.headers)


def test_create_and_list_own(client, world):
    r = _create(client, world["owner"])
    assert r.status_code == 201, r.text
    c = r.json()
    assert c["status"] == "open" and c["flat_number"] == "A-101"
    assert c["resolved_at"] is None
    mine = client.get("/complaints", headers=world["owner"].headers).json()
    assert [x["id"] for x in mine] == [c["id"]]


def test_newest_first_and_trim(client, world):
    _create(client, world["owner"], title="  First  ")
    second = _create(client, world["owner"], title="Second").json()
    mine = client.get("/complaints", headers=world["owner"].headers).json()
    assert mine[0]["id"] == second["id"]
    assert mine[1]["title"] == "First"


def test_others_cannot_see(client, world):
    _create(client, world["owner"])
    for who in ("tenant", "landlord", "stranger", "secretary"):
        assert client.get("/complaints", headers=world[who].headers).json() == []


def test_stranger_403(client, world):
    assert _create(client, world["stranger"]).status_code == 403


@pytest.mark.parametrize(
    "over",
    [
        {"title": "   "},
        {"title": ""},
        {"description": "  "},
        {"category": "weather"},
        {"title": "x" * 121},
        {"description": "x" * 2001},
    ],
)
def test_validation(client, world, over):
    assert _create(client, world["owner"], **over).status_code == 422


def test_flat_id_rules(client, world):
    assert _create(client, world["owner"], flat_id=world["b202"]).status_code == 404
    assert _create(client, world["owner"], flat_id=world["x1"]).status_code == 404
    r = _create(client, world["tenant"], flat_id=world["b202"])
    assert r.status_code == 201 and r.json()["flat_number"] == "B-202"


def test_admin_list_and_filter(client, world):
    a = _create(client, world["owner"]).json()
    b = _create(client, world["tenant"], category="lift").json()
    client.patch(f"/secretary/complaints/{b['id']}", json={"status": "in_progress"},
                 headers=world["secretary"].headers)
    rows = client.get("/secretary/complaints", headers=world["secretary"].headers).json()
    assert {r["id"] for r in rows} == {a["id"], b["id"]}
    by_id = {r["id"]: r for r in rows}
    assert by_id[a["id"]]["flat_number"] == "A-101"
    assert by_id[a["id"]]["created_by_email"] == "owner@example.com"
    assert by_id[a["id"]]["created_by_name"] == "owner"
    f = client.get("/secretary/complaints?status=open", headers=world["secretary"].headers).json()
    assert [r["id"] for r in f] == [a["id"]]
    f = client.get("/secretary/complaints?status=in_progress",
                   headers=world["secretary"].headers).json()
    assert [r["id"] for r in f] == [b["id"]]
    bad = client.get("/secretary/complaints?status=nope", headers=world["secretary"].headers)
    assert bad.status_code == 422


def test_admin_update_status_and_note(client, world):
    c = _create(client, world["owner"]).json()
    url = f"/secretary/complaints/{c['id']}"
    h = world["secretary"].headers
    r = client.patch(url, json={"status": "resolved", "admin_note": " Fixed today "}, headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "resolved"
    assert r.json()["resolved_at"] is not None
    assert r.json()["admin_note"] == "Fixed today"
    r = client.patch(url, json={"status": "open"}, headers=h)
    assert r.json()["resolved_at"] is None
    assert r.json()["admin_note"] == "Fixed today"  # note kept when omitted
    assert client.patch(url, json={"status": "bogus"}, headers=h).status_code == 422
    assert client.patch(url, json={"status": "open", "admin_note": "x" * 1001},
                        headers=h).status_code == 422
    mine = client.get("/complaints", headers=world["owner"].headers).json()
    assert mine[0]["status"] == "open" and mine[0]["admin_note"] == "Fixed today"


def test_non_admin_403(client, world):
    c = _create(client, world["owner"]).json()
    for who in ("owner", "guard", "stranger"):
        h = world[who].headers
        assert client.get("/secretary/complaints", headers=h).status_code == 403
        assert client.patch(f"/secretary/complaints/{c['id']}", json={"status": "resolved"},
                            headers=h).status_code == 403


def test_other_society_admin_404(client, world):
    c = _create(client, world["owner"]).json()
    h = world["secretary2"].headers
    assert client.get("/secretary/complaints", headers=h).json() == []
    r = client.patch(f"/secretary/complaints/{c['id']}", json={"status": "resolved"}, headers=h)
    assert r.status_code == 404
    assert client.patch("/secretary/complaints/99999", json={"status": "open"},
                        headers=world["secretary"].headers).status_code == 404
