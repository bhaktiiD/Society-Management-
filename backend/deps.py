"""Authorization layer.

Authentication = Supabase JWT (Google or email/password) verified in auth.py.
Authorization = LIVE database lookups of memberships on every request, so
revoking a membership takes effect immediately (no waiting for token expiry).
"""
import time
import uuid
from dataclasses import dataclass
from datetime import date

from fastapi import Depends, HTTPException
from sqlalchemy import func, or_, text
from sqlalchemy.orm import Session

from auth import get_current_user
from database import SessionLocal
from models import (
    AuditEvent,
    Flat,
    FlatMembership,
    GuardMembership,
    Invite,
    SocietyAdminMembership,
    User,
)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def audit(db: Session, actor, society_id, action, resource_type, resource_id, data=None):
    db.add(
        AuditEvent(
            actor_user_id=actor.id if actor else None,
            society_id=society_id,
            action=action,
            resource_type=resource_type,
            resource_id=str(resource_id),
            data=data,
        )
    )


# ---------------------------------------------------------------- identity
# Remembered per process so we do not re-ask the database on every request.
_has_auth_schema: bool | None = None
_verified_users: set[str] = set()
_claim_checked: dict[str, float] = {}
_CLAIM_INTERVAL_SECONDS = 60


def _email_verified(db: Session, claims: dict) -> bool:
    """Has this person proven they own the email?

    Invites are claimed by email, so an unverified email must never claim one
    (anyone could sign up with an owner's address before the owner does).
    On Supabase we ask the auth schema directly (authoritative). Elsewhere,
    e.g. the local test database, fall back to the token's metadata.
    """
    global _has_auth_schema
    sub = str(claims.get("sub"))
    if sub in _verified_users:  # once confirmed, always confirmed
        return True
    if _has_auth_schema is None:
        _has_auth_schema = bool(db.execute(text("select to_regclass('auth.users')")).scalar())
    if _has_auth_schema:
        verified = bool(
            db.execute(
                text("select email_confirmed_at is not null from auth.users where id = :id"),
                {"id": sub},
            ).scalar()
        )
    else:
        verified = bool((claims.get("user_metadata") or {}).get("email_verified"))
    if verified:
        _verified_users.add(sub)
    return verified


def current_user(
    claims: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> User:
    """Find-or-create the app user for this Supabase identity, then claim any
    pending invites addressed to their (verified) email."""
    sub = claims.get("sub")
    email = (claims.get("email") or "").lower()
    if not sub or not email:
        raise HTTPException(401, "Invalid authentication token")

    user_id = uuid.UUID(sub)
    user = db.get(User, user_id)
    changed = False
    if user is None:
        changed = True
        meta = claims.get("user_metadata") or {}
        user = User(
            id=user_id,
            email=email,
            full_name=(meta.get("full_name") or meta.get("name") or email.split("@")[0])[:100],
        )
        db.add(user)
        db.flush()

    # Look for invites at most once a minute per person (not on every request).
    now = time.monotonic()
    if now - _claim_checked.get(sub, -1e9) >= _CLAIM_INTERVAL_SECONDS and _email_verified(db, claims):
        _claim_checked[sub] = now
        changed = _claim_invites(db, user) or changed

    if changed:  # a COMMIT is a network round trip; skip it when nothing changed
        db.commit()
    return user


def _claim_invites(db: Session, user: User) -> bool:
    invites = (
        db.query(Invite)
        .filter(Invite.accepted_at.is_(None), func.lower(Invite.email) == user.email.lower())
        .with_for_update()  # a concurrent claim waits, then finds the invite already accepted
        .all()
    )
    for inv in invites:
        if inv.role in ("owner", "tenant"):
            db.add(
                FlatMembership(
                    flat_id=inv.flat_id,
                    user_id=user.id,
                    kind=inv.role,
                    is_resident=inv.is_resident,
                    start_date=date.today(),
                )
            )
        elif inv.role == "secretary":
            db.add(SocietyAdminMembership(society_id=inv.society_id, user_id=user.id))
        elif inv.role == "guard":
            db.add(GuardMembership(society_id=inv.society_id, user_id=user.id))
        inv.accepted_at = func.now()
        # Use the admin-entered details, but never overwrite what the person chose.
        if inv.full_name and user.full_name == user.email.split("@")[0][:100]:
            user.full_name = inv.full_name
        if inv.phone and not user.phone:
            user.phone = inv.phone
        audit(db, user, inv.society_id, "invite.accepted", "invite", inv.id, {"role": inv.role})
    return bool(invites)


# ------------------------------------------------------------- memberships
def current_flat_memberships(db: Session, user_id) -> list[FlatMembership]:
    today = date.today()
    return (
        db.query(FlatMembership)
        .join(Flat, Flat.id == FlatMembership.flat_id)
        .filter(
            FlatMembership.user_id == user_id,
            FlatMembership.start_date <= today,
            or_(FlatMembership.end_date.is_(None), FlatMembership.end_date >= today),
        )
        .all()
    )


def secretary_society_ids(db: Session, user_id) -> list[int]:
    rows = (
        db.query(SocietyAdminMembership.society_id)
        .filter(
            SocietyAdminMembership.user_id == user_id,
            SocietyAdminMembership.revoked_at.is_(None),
        )
        .all()
    )
    return [r[0] for r in rows]


def guard_society_ids(db: Session, user_id) -> list[int]:
    rows = (
        db.query(GuardMembership.society_id)
        .filter(GuardMembership.user_id == user_id, GuardMembership.revoked_at.is_(None))
        .all()
    )
    return [r[0] for r in rows]


def build_roles(db: Session, user: User) -> dict:
    flats = []
    for m in current_flat_memberships(db, user.id):
        flats.append(
            {
                "flat_id": m.flat_id,
                "flat_number": m.flat.flat_number,
                "society_id": m.flat.society_id,
                "kind": m.kind,
                "is_resident": m.is_resident,
            }
        )
    return {
        "secretary_of": secretary_society_ids(db, user.id),
        "guard_of": guard_society_ids(db, user.id),
        "flats": flats,
    }


# ------------------------------------------------------------- role guards
@dataclass
class SocietyContext:
    user: User
    society_id: int


def require_secretary(
    user: User = Depends(current_user), db: Session = Depends(get_db)
) -> SocietyContext:
    ids = secretary_society_ids(db, user.id)
    if not ids:
        raise HTTPException(403, "Only the society admin can do this.")
    return SocietyContext(user=user, society_id=ids[0])


def require_guard(
    user: User = Depends(current_user), db: Session = Depends(get_db)
) -> SocietyContext:
    ids = guard_society_ids(db, user.id)
    if not ids:
        raise HTTPException(403, "Only security guards can do this.")
    return SocietyContext(user=user, society_id=ids[0])


def user_flat_ids(db: Session, user_id, *, only_residents=False, only_owners=False) -> list[int]:
    ms = current_flat_memberships(db, user_id)
    if only_residents:
        ms = [m for m in ms if m.is_resident]
    if only_owners:
        ms = [m for m in ms if m.kind == "owner"]
    return [m.flat_id for m in ms]


def co_owner_payable_flat_ids(db: Session, user_id, charges) -> set[int]:
    """Flats where `user_id` may pay charges billed to ANOTHER person.

    Rule: the user is a current OWNER of the flat, and the person the charge was
    billed to is also an owner of it (a co-owner) or no longer a member. Charges
    billed to a tenant stay with that tenant. Used by the bill list and by
    payment intents so both always agree.
    """
    mine = set(user_flat_ids(db, user_id, only_owners=True))
    flat_ids = {c.flat_id for c in charges if c.flat_id in mine and c.responsible_user_id != user_id}
    if not flat_ids:
        return set()
    today = date.today()
    rows = (
        db.query(FlatMembership.flat_id, FlatMembership.user_id, FlatMembership.kind)
        .filter(
            FlatMembership.flat_id.in_(flat_ids),
            FlatMembership.start_date <= today,
            or_(FlatMembership.end_date.is_(None), FlatMembership.end_date >= today),
        )
        .all()
    )
    kinds: dict[tuple[int, object], set[str]] = {}
    for fid, uid, kind in rows:
        kinds.setdefault((fid, uid), set()).add(kind)
    ok = set()
    for c in charges:
        if c.flat_id not in mine or c.responsible_user_id == user_id:
            continue
        k = kinds.get((c.flat_id, c.responsible_user_id))
        if k is None or "owner" in k:
            ok.add(c.id)
    return ok


def pick_responsible(db: Session, flat_id: int, kind: str) -> FlatMembership | None:
    """The current owner/tenant of a flat who should be billed (oldest first)."""
    today = date.today()
    return (
        db.query(FlatMembership)
        .filter(
            FlatMembership.flat_id == flat_id,
            FlatMembership.kind == kind,
            FlatMembership.start_date <= today,
            or_(FlatMembership.end_date.is_(None), FlatMembership.end_date >= today),
        )
        .order_by(FlatMembership.start_date, FlatMembership.id)
        .first()
    )


def current_residents_of_flat(db: Session, flat_id: int) -> list[uuid.UUID]:
    """Who may approve guests: current registered OCCUPANTS only.

    For a rented flat the non-resident owner has is_resident=False and is
    therefore excluded; for an owner-occupied flat the resident owner counts.
    """
    today = date.today()
    rows = (
        db.query(FlatMembership.user_id)
        .filter(
            FlatMembership.flat_id == flat_id,
            FlatMembership.is_resident.is_(True),
            FlatMembership.start_date <= today,
            or_(FlatMembership.end_date.is_(None), FlatMembership.end_date >= today),
        )
        .all()
    )
    return [r[0] for r in rows]
