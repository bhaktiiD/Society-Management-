"""Profile photo endpoints: raw-body upload, owner-only access."""
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + b"\x00" * 20
JPG = b"\xff\xd8\xff\xe0" + b"\x00" * 30


def put(client, who, body, ctype="image/png"):
    return client.put("/me/avatar", content=body, headers={**who.headers, "content-type": ctype})


def test_me_null_before_and_int_after(client, world):
    h = world["owner"].headers
    assert client.get("/me", headers=h).json()["avatar_version"] is None
    r = put(client, world["owner"], PNG)
    assert r.status_code == 200 and isinstance(r.json()["avatar_version"], int)
    me = client.get("/me", headers=h).json()
    assert me["avatar_version"] == r.json()["avatar_version"]
    assert "avatar" not in me and PNG.hex() not in str(me)


def test_get_returns_same_bytes_and_cache_header(client, world):
    h = world["owner"].headers
    put(client, world["owner"], PNG)
    r = client.get("/me/avatar", headers=h)
    assert r.status_code == 200 and r.content == PNG
    assert r.headers["content-type"] == "image/png"
    assert r.headers["cache-control"] == "private, max-age=86400"
    put(client, world["owner"], JPG, "image/jpeg")
    r = client.get("/me/avatar", headers=h)
    assert r.content == JPG and r.headers["content-type"] == "image/jpeg"


def test_replace_version_strictly_increases(client, world):
    v1 = put(client, world["owner"], PNG).json()["avatar_version"]
    v2 = put(client, world["owner"], PNG).json()["avatar_version"]
    v3 = put(client, world["owner"], JPG, "image/jpeg").json()["avatar_version"]
    assert v1 < v2 < v3


def test_delete_clears_and_is_idempotent(client, world):
    h = world["owner"].headers
    put(client, world["owner"], PNG)
    assert client.delete("/me/avatar", headers=h).status_code == 204
    assert client.get("/me/avatar", headers=h).status_code == 404
    assert client.get("/me", headers=h).json()["avatar_version"] is None
    assert client.delete("/me/avatar", headers=h).status_code == 204


def test_rejections(client, world):
    o = world["owner"]
    assert put(client, o, PNG, "text/plain").status_code == 415
    assert put(client, o, JPG, "image/png").status_code == 422
    assert put(client, o, b"", "image/png").status_code == 422
    assert put(client, o, PNG + b"\x00" * (400 * 1024), "image/png").status_code == 413
    assert client.get("/me", headers=o.headers).json()["avatar_version"] is None


def test_owner_only(client, world):
    put(client, world["owner"], PNG)
    assert client.get("/me/avatar", headers=world["tenant"].headers).status_code == 404
    put(client, world["tenant"], JPG, "image/jpeg")
    assert client.get("/me/avatar", headers=world["owner"].headers).content == PNG
    assert client.get("/me/avatar", headers=world["tenant"].headers).content == JPG
