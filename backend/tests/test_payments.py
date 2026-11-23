"""PayEngine invariants: partial payments, idempotency, signatures, recovery."""
import hashlib
import hmac
import json
import threading
from datetime import date, timedelta

import gateway
import pytest

from models import GatewayPayment, PaymentAllocation


@pytest.fixture()
def fake_gateway(monkeypatch):
    """In-memory Razorpay: orders + payments we can 'capture'."""
    state = {"orders": {}, "payments": {}, "n": 0}

    def create_order(amount, receipt, notes):
        state["n"] += 1
        oid = f"order_{state['n']}"
        state["orders"][oid] = amount
        return {"id": oid}

    def fetch_payment(pid):
        return state["payments"][pid]

    def order_payments(oid):
        return [p for p in state["payments"].values() if p["order_id"] == oid]

    monkeypatch.setattr(gateway, "create_order", create_order)
    monkeypatch.setattr(gateway, "fetch_payment", fetch_payment)
    monkeypatch.setattr(gateway, "order_payments", order_payments)

    def capture(order_id, pid, status="captured"):
        state["payments"][pid] = {
            "id": pid, "order_id": order_id, "status": status,
            "amount": state["orders"][order_id],
        }

    state["capture"] = capture
    return state


def checkout_sig(order_id, pid):
    return hmac.new(b"test_secret", f"{order_id}|{pid}".encode(), hashlib.sha256).hexdigest()


def make_charge(client, world, amount=100_000):
    r = client.post(
        "/secretary/charges", headers=world["secretary"].headers,
        json={"flat_id": world["a101"], "charge_type": "maintenance", "title": "Nov maintenance",
              "amount_paise": amount, "due_date": str(date.today() + timedelta(days=5))},
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def start_intent(client, world, charge_id, amount, key):
    r = client.post("/payments/intents", headers=world["owner"].headers,
                    json={"charge_id": charge_id, "amount_paise": amount, "idempotency_key": key})
    assert r.status_code == 200, r.text
    return r.json()


def balance(client, world):
    return client.get("/charges", headers=world["owner"].headers).json()[0]


def webhook(client, event_id, order_id, pid, amount, event="payment.captured", sign=True):
    body = json.dumps({"event": event, "payload": {"payment": {"entity": {
        "id": pid, "order_id": order_id, "amount": amount}}}}).encode()
    sig = hmac.new(b"whsec_test", body, hashlib.sha256).hexdigest() if sign else "bad"
    return client.post("/webhooks/razorpay", content=body,
                       headers={"x-razorpay-signature": sig, "x-razorpay-event-id": event_id,
                                "content-type": "application/json"})


def test_partial_payments_400_then_600(client, world, fake_gateway):
    cid = make_charge(client, world, 100_000)  # Rs 1,000
    i1 = start_intent(client, world, cid, 40_000, "key-aaaaaaaa")
    fake_gateway["capture"](i1["order_id"], "pay_1")
    r = client.post("/payments/verify", headers=world["owner"].headers, json={
        "razorpay_order_id": i1["order_id"], "razorpay_payment_id": "pay_1",
        "razorpay_signature": checkout_sig(i1["order_id"], "pay_1")})
    assert r.json()["status"] == "paid"
    b = balance(client, world)
    assert (b["paid_paise"], b["balance_paise"], b["status"]) == (40_000, 60_000, "partial")

    i2 = start_intent(client, world, cid, 60_000, "key-bbbbbbbb")
    fake_gateway["capture"](i2["order_id"], "pay_2")
    client.post("/payments/verify", headers=world["owner"].headers, json={
        "razorpay_order_id": i2["order_id"], "razorpay_payment_id": "pay_2",
        "razorpay_signature": checkout_sig(i2["order_id"], "pay_2")})
    b = balance(client, world)
    assert (b["balance_paise"], b["status"]) == (0, "paid")


def test_cannot_pay_more_than_balance_or_float_amounts(client, world, fake_gateway):
    cid = make_charge(client, world, 100_000)
    r = client.post("/payments/intents", headers=world["owner"].headers,
                    json={"charge_id": cid, "amount_paise": 100_001, "idempotency_key": "key-cccccccc"})
    assert r.status_code == 422
    r = client.post("/payments/intents", headers=world["owner"].headers,
                    json={"charge_id": cid, "amount_paise": 10.5, "idempotency_key": "key-dddddddd"})
    assert r.status_code == 422


def test_duplicate_webhook_allocates_once(client, world, fake_gateway, db):
    cid = make_charge(client, world, 100_000)
    i = start_intent(client, world, cid, 100_000, "key-eeeeeeee")
    fake_gateway["capture"](i["order_id"], "pay_9")
    assert webhook(client, "evt_1", i["order_id"], "pay_9", 100_000).json()["status"] == "ok"
    assert webhook(client, "evt_1", i["order_id"], "pay_9", 100_000).json()["status"] == "duplicate"
    # Same payment redelivered under a *different* event id must also be safe.
    webhook(client, "evt_2", i["order_id"], "pay_9", 100_000)
    assert db.query(GatewayPayment).count() == 1
    assert db.query(PaymentAllocation).count() == 1
    assert balance(client, world)["balance_paise"] == 0


def test_verify_and_webhook_converge_on_one_payment(client, world, fake_gateway, db):
    cid = make_charge(client, world, 100_000)
    i = start_intent(client, world, cid, 100_000, "key-ffffffff")
    fake_gateway["capture"](i["order_id"], "pay_7")
    client.post("/payments/verify", headers=world["owner"].headers, json={
        "razorpay_order_id": i["order_id"], "razorpay_payment_id": "pay_7",
        "razorpay_signature": checkout_sig(i["order_id"], "pay_7")})
    webhook(client, "evt_x", i["order_id"], "pay_7", 100_000)
    assert db.query(PaymentAllocation).count() == 1


def test_invalid_signatures_rejected(client, world, fake_gateway, db):
    cid = make_charge(client, world, 100_000)
    i = start_intent(client, world, cid, 100_000, "key-gggggggg")
    fake_gateway["capture"](i["order_id"], "pay_5")
    r = client.post("/payments/verify", headers=world["owner"].headers, json={
        "razorpay_order_id": i["order_id"], "razorpay_payment_id": "pay_5",
        "razorpay_signature": "forged"})
    assert r.status_code == 400
    assert webhook(client, "evt_bad", i["order_id"], "pay_5", 100_000, sign=False).status_code == 400
    assert db.query(PaymentAllocation).count() == 0
    assert balance(client, world)["balance_paise"] == 100_000


def test_client_callback_alone_never_marks_paid(client, world, fake_gateway):
    """Valid-looking signature, but the gateway says the payment isn't captured."""
    cid = make_charge(client, world, 100_000)
    i = start_intent(client, world, cid, 100_000, "key-hhhhhhhh")
    fake_gateway["capture"](i["order_id"], "pay_3", status="failed")
    r = client.post("/payments/verify", headers=world["owner"].headers, json={
        "razorpay_order_id": i["order_id"], "razorpay_payment_id": "pay_3",
        "razorpay_signature": checkout_sig(i["order_id"], "pay_3")})
    assert r.json()["status"] == "pending"
    assert balance(client, world)["paid_paise"] == 0


def test_repeated_initiation_is_idempotent(client, world, fake_gateway):
    cid = make_charge(client, world)
    a = start_intent(client, world, cid, 50_000, "key-iiiiiiii")
    b = start_intent(client, world, cid, 50_000, "key-iiiiiiii")
    assert a["intent_id"] == b["intent_id"] and a["order_id"] == b["order_id"]
    assert len(fake_gateway["orders"]) == 1


def test_recovery_after_lost_callback(client, world, fake_gateway):
    """App died after paying: status endpoint reconciles with the gateway."""
    cid = make_charge(client, world, 100_000)
    i = start_intent(client, world, cid, 100_000, "key-jjjjjjjj")
    fake_gateway["capture"](i["order_id"], "pay_lost")  # no verify, no webhook
    r = client.get(f"/payments/intents/{i['intent_id']}/status", headers=world["owner"].headers)
    assert r.json()["status"] == "paid" and r.json()["balance_paise"] == 0


def test_concurrent_confirmation_allocates_once(client, world, fake_gateway, db):
    cid = make_charge(client, world, 100_000)
    i = start_intent(client, world, cid, 100_000, "key-kkkkkkkk")
    fake_gateway["capture"](i["order_id"], "pay_race")
    body = {"razorpay_order_id": i["order_id"], "razorpay_payment_id": "pay_race",
            "razorpay_signature": checkout_sig(i["order_id"], "pay_race")}
    codes = []

    def go():
        codes.append(client.post("/payments/verify", headers=world["owner"].headers, json=body).status_code)

    ts = [threading.Thread(target=go) for _ in range(6)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert all(c == 200 for c in codes)
    db.expire_all()
    assert db.query(GatewayPayment).count() == 1
    assert db.query(PaymentAllocation).count() == 1


def test_other_users_cannot_pay_or_see_the_charge(client, world, fake_gateway):
    cid = make_charge(client, world)
    for who in ("tenant", "landlord", "stranger"):
        r = client.post("/payments/intents", headers=world[who].headers,
                        json={"charge_id": cid, "amount_paise": 1000, "idempotency_key": "key-llllllll"})
        assert r.status_code == 404
        assert client.get("/charges", headers=world[who].headers).json() == []


def test_webhook_stored_but_never_processed_is_retried_not_dropped(client, world, fake_gateway, db):
    """If the server crashed after saving the event but before allocating, Razorpay's
    retry (same event id) must still complete the payment."""
    from datetime import datetime, timezone
    from models import WebhookEvent
    cid = make_charge(client, world, 100_000)
    i = start_intent(client, world, cid, 100_000, "key-retry-xx")
    fake_gateway["capture"](i["order_id"], "pay_retry")
    db.add(WebhookEvent(event_id="evt_retry", event_type="payment.captured", payload={}))  # processed_at stays NULL
    db.commit()
    assert webhook(client, "evt_retry", i["order_id"], "pay_retry", 100_000).json()["status"] == "ok"
    assert balance(client, world)["balance_paise"] == 0
    assert webhook(client, "evt_retry", i["order_id"], "pay_retry", 100_000).json()["status"] == "duplicate"
    db.expire_all()
    assert db.query(PaymentAllocation).count() == 1


def test_cannot_open_second_intent_while_first_is_in_flight(client, world, fake_gateway):
    cid = make_charge(client, world, 100_000)
    start_intent(client, world, cid, 100_000, "key-inflight1")
    r = client.post("/payments/intents", headers=world["owner"].headers,
                    json={"charge_id": cid, "amount_paise": 100_000, "idempotency_key": "key-inflight2"})
    assert r.status_code == 409
