"""Push notifications via Firebase Cloud Messaging.

Disabled (silent no-op) until FIREBASE_CREDENTIALS points to a service-account
JSON file. Failures never break the request that triggered them: push is a
convenience, the database is the source of truth.
"""
import logging
import os

from sqlalchemy.orm import Session

from models import DeviceToken

log = logging.getLogger("societyos.push")
_app = None
_tried = False


def _init():
    global _app, _tried
    if _tried:
        return _app
    _tried = True
    path = os.getenv("FIREBASE_CREDENTIALS")
    if not path or not os.path.exists(path):
        log.info("Push disabled: FIREBASE_CREDENTIALS not set")
        return None
    try:
        import firebase_admin
        from firebase_admin import credentials

        _app = firebase_admin.initialize_app(credentials.Certificate(path))
    except Exception:  # pragma: no cover
        log.exception("Could not initialise Firebase")
        _app = None
    return _app


def notify_users(db: Session, user_ids, title: str, body: str, data: dict | None = None,
                 urgent: bool = False):
    if not user_ids or _init() is None:
        return
    tokens = [
        t.token
        for t in db.query(DeviceToken).filter(DeviceToken.user_id.in_(list(user_ids))).all()
    ]
    if not tokens:
        return
    try:
        from firebase_admin import messaging

        kwargs = {}
        if urgent:
            kwargs["android"] = messaging.AndroidConfig(
                priority="high",
                ttl=0,
                notification=messaging.AndroidNotification(
                    channel_id="emergency_alarm",
                    sound="siren",
                    priority="max",
                    default_vibrate_timings=True,
                    visibility="public",
                ),
            )
            kwargs["apns"] = messaging.APNSConfig(
                headers={"apns-priority": "10"},
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default", interruption_level="time-sensitive")
                ),
            )
        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            **kwargs,
        )
        messaging.send_each_for_multicast(message)
    except Exception:  # pragma: no cover
        log.exception("Push send failed")
