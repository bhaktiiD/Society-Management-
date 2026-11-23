def _add(client, who, **kw):
    body = {"name": "Police", "phone": "100", "category": "emergency", **kw}
    return client.post("/secretary/contacts", json=body, headers=who.headers)


def _names(client, who):
    r = client.get("/contacts", headers=who.headers)
    assert r.status_code == 200
    return [c["name"] for c in r.json()]


def test_admin_crud(client, world):
    r = _add(client, world["secretary"], name="  Ram  Plumber ", label=" 24x7 ", category="service")
    assert r.status_code == 201
    c = r.json()
    assert c["name"] == "Ram Plumber" and c["label"] == "24x7" and c["sort_order"] == 0
    r = client.put(
        f"/secretary/contacts/{c['id']}",
        json={"name": "Ram", "phone": "+91 98765-43210", "category": "staff", "sort_order": 5},
        headers=world["secretary"].headers,
    )
    assert r.status_code == 200
    assert r.json()["category"] == "staff" and r.json()["label"] is None
    assert client.delete(f"/secretary/contacts/{c['id']}", headers=world["secretary"].headers).status_code == 204
    assert _names(client, world["secretary"]) == []
    assert client.delete(f"/secretary/contacts/{c['id']}", headers=world["secretary"].headers).status_code == 404


def test_ordering(client, world):
    s = world["secretary"]
    _add(client, s, name="Zed", category="service")
    _add(client, s, name="Bob", category="staff", sort_order=2)
    _add(client, s, name="Amy", category="staff", sort_order=1)
    _add(client, s, name="Fire", category="emergency", sort_order=9)
    _add(client, s, name="Ambulance", category="emergency", sort_order=9)
    assert _names(client, s) == ["Ambulance", "Fire", "Amy", "Bob", "Zed"]


def test_visibility_by_role(client, world):
    _add(client, world["secretary"], name="S1 Police")
    _add(client, world["secretary2"], name="S2 Police")
    for who in ("owner", "tenant", "landlord", "guard", "secretary"):
        assert _names(client, world[who]) == ["S1 Police"], who
    assert _names(client, world["secretary2"]) == ["S2 Police"]
    assert _names(client, world["stranger"]) == []


def test_cross_society_blocked(client, world):
    cid = _add(client, world["secretary"]).json()["id"]
    h = world["secretary2"].headers
    body = {"name": "X", "phone": "123"}
    assert client.put(f"/secretary/contacts/{cid}", json=body, headers=h).status_code == 404
    assert client.delete(f"/secretary/contacts/{cid}", headers=h).status_code == 404
    assert _names(client, world["secretary"]) == ["Police"]


def test_non_admin_forbidden(client, world):
    cid = _add(client, world["secretary"]).json()["id"]
    for who in ("owner", "tenant", "guard", "stranger"):
        h = world[who].headers
        body = {"name": "X", "phone": "123"}
        assert client.post("/secretary/contacts", json=body, headers=h).status_code == 403
        assert client.put(f"/secretary/contacts/{cid}", json=body, headers=h).status_code == 403
        assert client.delete(f"/secretary/contacts/{cid}", headers=h).status_code == 403


def test_validation(client, world):
    bad = [
        {"name": "   ", "phone": "100"},
        {"name": "", "phone": "100"},
        {"name": "A", "phone": "abc"},
        {"name": "A", "phone": "12"},
        {"name": "A", "phone": "1" * 21},
        {"name": "A", "phone": "100", "category": "vip"},
        {"name": "A" * 101, "phone": "100"},
        {"name": "A", "phone": "100", "label": "L" * 61},
        {"name": "A", "phone": "100", "sort_order": 1001},
        {"name": "A", "phone": "100", "sort_order": -1},
    ]
    for body in bad:
        r = client.post("/secretary/contacts", json=body, headers=world["secretary"].headers)
        assert r.status_code == 422, body
    assert _names(client, world["secretary"]) == []
