"""Thin Razorpay wrapper (TEST MODE keys only). Secrets stay server-side.

Kept in one module so tests can monkeypatch the network calls.
"""
import hashlib
import hmac
import os

import razorpay


def _key_id() -> str:
    return os.getenv("RAZORPAY_KEY_ID", "")


def _key_secret() -> str:
    return os.getenv("RAZORPAY_KEY_SECRET", "")


def _webhook_secret() -> str:
    return os.getenv("RAZORPAY_WEBHOOK_SECRET", "")


def public_key_id() -> str:
    return _key_id()


def _client() -> razorpay.Client:
    if not _key_id() or not _key_secret():
        raise RuntimeError("Razorpay test keys are not configured")
    return razorpay.Client(auth=(_key_id(), _key_secret()))


def create_order(amount_paise: int, receipt: str, notes: dict) -> dict:
    return _client().order.create(
        {"amount": amount_paise, "currency": "INR", "receipt": receipt, "notes": notes}
    )


def fetch_payment(payment_id: str) -> dict:
    return _client().payment.fetch(payment_id)


def order_payments(order_id: str) -> list[dict]:
    return _client().order.payments(order_id).get("items", [])


def verify_checkout_signature(order_id: str, payment_id: str, signature: str) -> bool:
    expected = hmac.new(
        _key_secret().encode(), f"{order_id}|{payment_id}".encode(), hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature or "")


def verify_webhook_signature(raw_body: bytes, signature: str) -> bool:
    secret = _webhook_secret()
    if not secret:
        return False
    expected = hmac.new(secret.encode(), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature or "")
