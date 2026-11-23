"""Role-based security, invites, responsibility snapshots, guest approvals."""
import threading
from datetime import date, timedelta, timezone, datetime

from models import FlatMembership, GuestRequest

DUE = str(date.today() + timedelta(days=5))


# ------------------------------------------------------------ role security
def test_only_secretary_can_use_secretary_endpoints(client, world):
    for who in ("owner", "tenant", "guard", "stranger"):
        assert client.get("/secretary/charges", headers=world[who].headers).status_code == 403
        assert client.post("/secretary/notices", headers=world[who].headers,
                           json={"title": "x", "body": "y"}).status_code == 403
    assert client.get("/secretary/charges", headers=world["secretary"].headers).status_code == 200


def test_cross_society_isolation(client, world):
    # Secretary of S2 cannot bill a flat of S1 (and learns nothing about it).
    r = client.post("/secretary/charges", headers=world["secretary2"].headers,
                    json={"flat_id": world["a101"], "charge_type": "maintenance", "title": "x",
                          "amount_paise": 1000, "due_date": DUE})
    assert r.status_code == 404
    assert client.get("/secretary/flats", headers=world["secretary2"].headers).json()[0]["flat_number"] == "X-1"


def test_guard_cannot_do_resident_things_and_vice_versa(client, world):
    assert client.post("/guard/guests", headers=world["owner"].headers,
                       json={"flat_number": "A-101", "guest_name": "G"}).status_code == 403
    assert client.get("/secretary/collections", headers=world["guard"].headers).status_code == 403


def test_pending_user_has_no_access(client, world):
    from conftest import Actor
    newbie = Actor("newbie@example.com")
    me = client.get("/me", headers=newbie.headers).json()
    assert me["status"] == "pending" and not (me["is_owner"] or me["is_secretary"])
    assert client.get("/secretary/charges", headers=newbie.headers).status_code == 403
    assert client.get("/charges", headers=newbie.headers).json() == []


def test_invite_grants_role_on_first_login(client, world):
    from conftest import Actor
    r = client.post("/secretary/invites", headers=world["secretary"].headers,
                    json={"email": "New.Tenant@Example.com", "role": "tenant", "flat_id": world["a101"]})
    assert r.status_code == 201
    newbie = Actor("new.tenant@example.com")
    me = client.get("/me", headers=newbie.headers).json()
    assert me["status"] == "active" and me["is_tenant"] is True
    assert me["roles"]["flats"][0]["flat_number"] == "A-101"


def test_cannot_invite_into_another_societys_flat(client, world):
    r = client.post("/secretary/invites", headers=world["secretary2"].headers,
                    json={"email": "a@example.com", "role": "owner", "flat_id": world["a101"]})
    assert r.status_code == 404


# ---------------------------------------------------- responsibility snapshot
def test_maintenance_billed_to_owner_and_snapshot_survives_move_out(client, world, db):
    r = client.post("/secretary/charges", headers=world["secretary"].headers,
                    json={"flat_id": world["b202"], "charge_type": "maintenance", "title": "Nov",
                          "amount_paise": 5000, "due_date": DUE})
    assert r.json()["responsible_user_id"] == str(world["landlord"].id)  # owner, not tenant
    # Landlord's membership ends later: the existing charge is still theirs.
    m = db.query(FlatMembership).filter_by(user_id=world["landlord"].id).one()
    m.end_date = date.today() - timedelta(days=1)
    db.commit()
    assert len(client.get("/charges", headers=world["landlord"].headers).json()) == 1


def test_festival_charge_can_target_tenant(client, world):
    r = client.post("/secretary/charges", headers=world["secretary"].headers,
                    json={"flat_id": world["b202"], "charge_type": "festival", "title": "Diwali",
                          "amount_paise": 2000, "due_date": DUE, "responsible": "tenant"})
    assert r.json()["responsible_user_id"] == str(world["tenant"].id)


# -------------------------------------------------------------- notices
def test_notice_visible_to_members_only(client, world):
    client.post("/secretary/notices", headers=world["secretary"].headers,
                json={"title": "Water cut", "body": "Tomorrow 10-12"})
    assert client.get("/notices", headers=world["tenant"].headers).json()[0]["title"] == "Water cut"
    assert client.get("/notices", headers=world["guard"].headers).json()[0]["title"] == "Water cut"
    assert client.get("/notices", headers=world["secretary2"].headers).json() == []
    assert client.get("/notices", headers=world["stranger"].headers).json() == []


# ---------------------------------------------------------- guest approvals
def ask(client, world, flat="B-202"):
    r = client.post("/guard/guests", headers=world["guard"].headers,
                    json={"flat_number": flat, "guest_name": "Ravi", "guest_phone": "9999999999"})
    assert r.status_code == 201, r.text
    return r.json()["id"]


def test_rented_flat_only_tenant_can_approve_not_landlord(client, world):
    gid = ask(client, world, "B-202")
    assert client.get("/guests/pending", headers=world["landlord"].headers).json() == []
    r = client.post(f"/guests/{gid}/decision", headers=world["landlord"].headers, json={"approve": True})
    assert r.status_code == 404
    r = client.post(f"/guests/{gid}/decision", headers=world["tenant"].headers, json={"approve": True})
    assert r.status_code == 200 and r.json()["status"] == "approved"


def test_owner_occupied_flat_owner_can_approve(client, world):
    gid = ask(client, world, "A-101")
    r = client.post(f"/guests/{gid}/decision", headers=world["owner"].headers, json={"approve": True})
    assert r.json()["status"] == "approved"


def test_first_decision_wins(client, world, db):
    from conftest import Actor
    # Give B-202 a second resident so two people can race.
    import models
    second = Actor("roommate@example.com")
    db.add(models.User(id=second.id, email=second.email, full_name="roommate"))
    db.flush()
    db.add(FlatMembership(flat_id=world["b202"], user_id=second.id, kind="tenant", is_resident=True,
                          start_date=date.today() - timedelta(days=1)))
    db.commit()
    gid = ask(client, world)
    a = client.post(f"/guests/{gid}/decision", headers=world["tenant"].headers, json={"approve": True})
    b = client.post(f"/guests/{gid}/decision", headers=second.headers, json={"approve": False})
    assert a.status_code == 200 and b.status_code == 409
    assert client.get("/guard/guests", headers=world["guard"].headers).json()[0]["status"] == "approved"


def test_concurrent_decisions_only_one_succeeds(client, world, db):
    from conftest import Actor
    import models
    second = Actor("roommate2@example.com")
    db.add(models.User(id=second.id, email=second.email, full_name="r2"))
    db.flush()
    db.add(FlatMembership(flat_id=world["b202"], user_id=second.id, kind="tenant", is_resident=True,
                          start_date=date.today() - timedelta(days=1)))
    db.commit()
    gid = ask(client, world)
    codes = []

    def go(h, approve):
        codes.append(client.post(f"/guests/{gid}/decision", headers=h, json={"approve": approve}).status_code)

    ts = [threading.Thread(target=go, args=(world["tenant"].headers, True)),
          threading.Thread(target=go, args=(second.headers, False))]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert sorted(codes) == [200, 409]


def test_checkin_requires_approval_is_single_use_and_checkout_idempotent(client, world):
    gid = ask(client, world)
    g = world["guard"].headers
    assert client.post(f"/guard/guests/{gid}/check-in", headers=g).status_code == 409  # not approved
    client.post(f"/guests/{gid}/decision", headers=world["tenant"].headers, json={"approve": True})
    assert client.post(f"/guard/guests/{gid}/check-in", headers=g).json()["status"] == "checked_in"
    assert client.post(f"/guard/guests/{gid}/check-in", headers=g).status_code == 409  # single use
    first = client.post(f"/guard/guests/{gid}/check-out", headers=g).json()
    second = client.post(f"/guard/guests/{gid}/check-out", headers=g).json()
    assert first["status"] == second["status"] == "checked_out"
    assert first["checked_out_at"] == second["checked_out_at"]


def test_expired_approval_cannot_be_used(client, world, db):
    gid = ask(client, world)
    client.post(f"/guests/{gid}/decision", headers=world["tenant"].headers, json={"approve": True})
    g = db.get(GuestRequest, gid)
    g.expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
    db.commit()
    assert client.post(f"/guard/guests/{gid}/check-in", headers=world["guard"].headers).status_code == 409


def test_pending_request_expires_and_cannot_be_approved(client, world, db):
    gid = ask(client, world)
    g = db.get(GuestRequest, gid)
    g.expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
    db.commit()
    r = client.post(f"/guests/{gid}/decision", headers=world["tenant"].headers, json={"approve": True})
    assert r.status_code == 409


def test_guard_cannot_touch_other_societys_flats_or_requests(client, world):
    r = client.post("/guard/guests", headers=world["guard"].headers,
                    json={"flat_number": "X-1", "guest_name": "G"})
    assert r.status_code == 404


def test_former_tenant_cannot_approve(client, world, db):
    gid = ask(client, world)
    m = db.query(FlatMembership).filter_by(user_id=world["tenant"].id).one()
    m.end_date = date.today() - timedelta(days=1)
    db.commit()
    r = client.post(f"/guests/{gid}/decision", headers=world["tenant"].headers, json={"approve": True})
    assert r.status_code == 404


# ------------------------------------------------- registration & admin tools
def test_unverified_email_cannot_claim_invite(client, world):
    """Anyone can sign up with someone else's email; only the verified owner
    of that mailbox may receive the pre-registered role."""
    from conftest import Actor
    client.post("/secretary/invites", headers=world["secretary"].headers,
                json={"email": "victim@example.com", "role": "owner", "flat_id": world["a101"]})
    attacker = Actor("victim@example.com")
    h = {**attacker.headers, "x-test-unverified": "1"}
    assert client.get("/me", headers=h).json()["status"] == "pending"
    # Once the real mailbox owner verifies, the invite is theirs.
    assert client.get("/me", headers=attacker.headers).json()["is_owner"] is True


def test_check_invite_is_public_and_one_shot(client, world):
    from conftest import Actor
    client.post("/secretary/invites", headers=world["secretary"].headers,
                json={"email": "Fresh.Owner@Example.com", "role": "owner", "flat_id": world["a101"]})
    assert client.post("/auth/check-invite", json={"email": "fresh.owner@example.com"}).json() == {"invited": True}
    assert client.post("/auth/check-invite", json={"email": "nobody@example.com"}).json() == {"invited": False}
    client.get("/me", headers=Actor("fresh.owner@example.com").headers)  # claims it
    assert client.post("/auth/check-invite", json={"email": "fresh.owner@example.com"}).json() == {"invited": False}


def test_revoke_pending_invite(client, world):
    r = client.post("/secretary/invites", headers=world["secretary"].headers,
                    json={"email": "oops@example.com", "role": "owner", "flat_id": world["a101"]})
    iid = r.json()["id"]
    flat = [f for f in client.get("/secretary/flats", headers=world["secretary"].headers).json()
            if f["id"] == world["a101"]][0]
    assert flat["pending_invites"][0]["email"] == "oops@example.com"
    assert client.delete(f"/secretary/invites/{iid}", headers=world["secretary2"].headers).status_code == 404
    assert client.delete(f"/secretary/invites/{iid}", headers=world["secretary"].headers).status_code == 204
    assert client.post("/auth/check-invite", json={"email": "oops@example.com"}).json() == {"invited": False}


def test_end_membership_removes_access_but_keeps_history(client, world, db):
    flats = client.get("/secretary/flats", headers=world["secretary"].headers).json()
    b202 = [f for f in flats if f["id"] == world["b202"]][0]
    tenant = [m for m in b202["members"] if m["kind"] == "tenant"][0]
    assert client.post(f"/secretary/memberships/{tenant['membership_id']}/end",
                       headers=world["secretary2"].headers).status_code == 404
    assert client.post(f"/secretary/memberships/{tenant['membership_id']}/end",
                       headers=world["secretary"].headers).status_code == 204
    db.expire_all()
    assert db.get(FlatMembership, tenant["membership_id"]) is not None  # row kept
    assert client.get("/me", headers=world["tenant"].headers).json()["status"] == "pending"


# ------------------------------------------------------ profile & society name
def test_user_can_set_own_display_name_and_phone(client, world):
    h = world["secretary"].headers
    r = client.patch("/me", headers=h, json={"full_name": "  Bhakti   Dhavulkar ", "phone": " 98765 43210 "})
    assert r.status_code == 200
    assert r.json()["full_name"] == "Bhakti Dhavulkar"      # trimmed, spaces collapsed
    assert r.json()["phone"] == "98765 43210"
    assert client.get("/me", headers=h).json()["full_name"] == "Bhakti Dhavulkar"
    # Roles and email cannot be changed through this endpoint.
    assert client.get("/me", headers=h).json()["is_secretary"] is True
    assert client.get("/me", headers=h).json()["email"] == "secretary@example.com"


def test_profile_name_validation_and_isolation(client, world):
    h = world["owner"].headers
    assert client.patch("/me", headers=h, json={"full_name": "   "}).status_code == 422
    assert client.patch("/me", headers=h, json={"full_name": ""}).status_code == 422
    assert client.patch("/me", headers=h, json={"full_name": "x" * 101}).status_code == 422
    client.patch("/me", headers=h, json={"full_name": "Owner One"})
    assert client.get("/me", headers=world["tenant"].headers).json()["full_name"] != "Owner One"


def test_only_admin_can_rename_society_and_only_their_own(client, world):
    h = world["secretary"].headers
    assert client.patch("/secretary/society", headers=world["owner"].headers, json={"name": "X"}).status_code == 403
    assert client.get("/secretary/society", headers=world["guard"].headers).status_code == 403
    assert client.patch("/secretary/society", headers=h, json={"name": "  Sunrise   Heights "}).json()["name"] == "Sunrise Heights"
    assert client.get("/secretary/society", headers=h).json()["name"] == "Sunrise Heights"
    assert client.get("/secretary/society", headers=world["secretary2"].headers).json()["name"] == "S2"
    assert client.patch("/secretary/society", headers=h, json={"name": " "}).status_code == 422


# ------------------------------------------------ add a resident (name, phone)
def test_invite_details_are_copied_to_the_profile_on_first_sign_in(client, world):
    from conftest import Actor
    r = client.post("/secretary/invites", headers=world["secretary"].headers, json={
        "email": "New.Resident@example.com", "role": "tenant", "flat_id": world["a101"],
        "full_name": "  Meera   Kapoor ", "phone": "98765 43210"})
    assert r.status_code == 201
    # The pending registration shows the details before they have signed up.
    flat = [f for f in client.get("/secretary/flats", headers=world["secretary"].headers).json()
            if f["id"] == world["a101"]][0]
    pend = flat["pending_invites"][0]
    assert (pend["full_name"], pend["phone"]) == ("Meera Kapoor", "98765 43210")
    # First sign-in: profile is filled from what the admin typed.
    me = client.get("/me", headers=Actor("new.resident@example.com").headers).json()
    assert me["full_name"] == "Meera Kapoor" and me["phone"] == "98765 43210"
    flat = [f for f in client.get("/secretary/flats", headers=world["secretary"].headers).json()
            if f["id"] == world["a101"]][0]
    tenant = [m for m in flat["members"] if m["kind"] == "tenant"][0]
    assert tenant["name"] == "Meera Kapoor" and tenant["phone"] == "98765 43210"


def test_invite_never_overwrites_a_name_the_person_already_chose(client, world):
    import deps
    from conftest import Actor
    person = Actor("chosen@example.com")
    client.get("/me", headers=person.headers)                      # account exists (pending)
    client.patch("/me", headers=person.headers, json={"full_name": "Chosen Name", "phone": "11111"})
    client.post("/secretary/invites", headers=world["secretary"].headers, json={
        "email": "chosen@example.com", "role": "owner", "flat_id": world["a101"],
        "full_name": "Admin Typed", "phone": "99999 99999"})
    deps._claim_checked.clear()                                    # skip the 60 s claim throttle
    me = client.get("/me", headers=person.headers).json()
    assert me["is_owner"] is True
    assert me["full_name"] == "Chosen Name" and me["phone"] == "11111"


def test_invite_validation_and_duplicates(client, world):
    h = world["secretary"].headers
    base = {"email": "dup@example.com", "role": "tenant", "flat_id": world["a101"]}
    assert client.post("/secretary/invites", headers=h, json={**base, "phone": "abc"}).status_code == 422
    assert client.post("/secretary/invites", headers=h, json={**base, "full_name": "x" * 101}).status_code == 422
    assert client.post("/secretary/invites", headers=h, json=base).status_code == 201
    assert client.post("/secretary/invites", headers=h, json=base).status_code == 409   # same email, same flat
