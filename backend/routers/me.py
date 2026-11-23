from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session, undefer

from deps import build_roles, current_user, get_db
from models import DeviceToken, Invite, User

router = APIRouter(tags=["me"])


def _version(ts: datetime | None) -> int | None:
    return int(ts.timestamp()) if ts else None


@router.get("/me")
def me(user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Profile + every role this person currently holds.

    The app routes on this. A user with no memberships is `pending`: Google
    login proved who they are, but nobody has granted them access yet.
    """
    roles = build_roles(db, user)
    has_access = bool(roles["secretary_of"] or roles["guard_of"] or roles["flats"])
    return {
        "id": str(user.id),
        "full_name": user.full_name,
        "email": user.email,
        "phone": user.phone,
        "status": "active" if has_access else "pending",
        "is_secretary": bool(roles["secretary_of"]),
        "is_guard": bool(roles["guard_of"]),
        "is_owner": any(f["kind"] == "owner" for f in roles["flats"]),
        "is_tenant": any(f["kind"] == "tenant" for f in roles["flats"]),
        "roles": roles,
        "avatar_version": _version(user.avatar_updated_at),
    }


class ProfileIn(BaseModel):
    full_name: str = Field(min_length=1, max_length=100)
    phone: str | None = Field(default=None, max_length=20)


@router.patch("/me")
def update_profile(
    body: ProfileIn, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    """Change my own display name and phone. Email and roles are not editable here."""
    name = " ".join(body.full_name.split())  # trim + collapse spaces
    if not name:
        raise HTTPException(422, "Please enter your name.")
    user.full_name = name
    user.phone = (body.phone or "").strip() or None
    db.commit()
    return me(user=user, db=db)


class EmailIn(BaseModel):
    email: str = Field(min_length=3, max_length=150)


@router.post("/auth/check-invite")
def check_invite(body: EmailIn, db: Session = Depends(get_db)):
    """Public: may this email create an account? Only if a secretary has
    pre-registered it and it has not been claimed yet. Reveals nothing else."""
    found = (
        db.query(Invite.id)
        .filter(
            Invite.accepted_at.is_(None),
            func.lower(Invite.email) == body.email.strip().lower(),
        )
        .first()
    )
    return {"invited": found is not None}


class DeviceTokenIn(BaseModel):
    token: str = Field(min_length=10, max_length=512)


@router.post("/me/device-token", status_code=204)
def register_device_token(
    body: DeviceTokenIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    existing = db.query(DeviceToken).filter(DeviceToken.token == body.token).first()
    if existing:
        existing.user_id = user.id  # token moved to a new login on this device
    else:
        db.add(DeviceToken(user_id=user.id, token=body.token))
    db.commit()


MAX_AVATAR_BYTES = 400 * 1024
AVATAR_TYPES = {"image/jpeg", "image/png", "image/webp"}


def _sniff(b: bytes) -> str | None:
    if b.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if b.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if b[:4] == b"RIFF" and b[8:12] == b"WEBP":
        return "image/webp"
    return None


@router.put("/me/avatar")
async def upload_avatar(
    request: Request,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    """Raw image bytes in the body. Only the account owner can set their photo."""
    ctype = (request.headers.get("content-type") or "").split(";")[0].strip().lower()
    if ctype not in AVATAR_TYPES:
        raise HTTPException(415, "Please choose a JPEG, PNG or WebP photo.")
    data = await request.body()
    if not data:
        raise HTTPException(422, "That file is not a valid image.")
    if len(data) > MAX_AVATAR_BYTES:
        raise HTTPException(413, "That photo is too large. Please choose a smaller one.")
    if _sniff(data) != ctype:
        raise HTTPException(422, "That file is not a valid image.")
    now = datetime.now(timezone.utc).replace(microsecond=0)
    old = user.avatar_updated_at
    if old is not None and now <= old.replace(microsecond=0):
        now = old.replace(microsecond=0) + timedelta(seconds=1)
    user.avatar = data
    user.avatar_content_type = ctype
    user.avatar_updated_at = now
    db.commit()
    return {"avatar_version": _version(now)}


@router.get("/me/avatar")
def get_avatar(user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = (
        db.query(User)
        .options(undefer(User.avatar))
        .filter(User.id == user.id)
        .one()
    )
    if not row.avatar:
        raise HTTPException(404, "No profile photo yet.")
    return Response(
        content=row.avatar,
        media_type=row.avatar_content_type or "image/jpeg",
        headers={"Cache-Control": "private, max-age=86400"},
    )


@router.delete("/me/avatar", status_code=204)
def delete_avatar(user: User = Depends(current_user), db: Session = Depends(get_db)):
    user.avatar = None
    user.avatar_content_type = None
    user.avatar_updated_at = None
    db.commit()
    return Response(status_code=204)
