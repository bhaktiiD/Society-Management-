"""SocietyOS data model.

Design rules (see architecture doc):
* Identity is separate from roles. `users.id` equals the Supabase auth `sub`.
* Ownership / occupancy / secretary / guard are effective-dated memberships,
  never a single `role` column.
* All money is integer paise. Constraints protect invariants in the database.
* Financial rows are append-oriented: payments and allocations are never edited.

NOTE: the legacy `apartments` / `residents` tables still exist in the database
but are intentionally no longer mapped here.
"""
import uuid
from datetime import date, datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    LargeBinary,
    String,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from database import Base


# --------------------------------------------------------------------------
# Identity & society structure
# --------------------------------------------------------------------------
class User(Base):
    __tablename__ = "users"

    # Equals Supabase auth.users.id (JWT `sub`).
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    email: Mapped[str] = mapped_column(String(150), unique=True, nullable=False)
    full_name: Mapped[str] = mapped_column(String(100), nullable=False)
    phone: Mapped[str | None] = mapped_column(String(20))
    # Profile photo (already resized by the app, <= ~400 KB). deferred: it is NOT
    # loaded with the user on every request, only when the avatar is fetched.
    avatar: Mapped[bytes | None] = mapped_column(LargeBinary, deferred=True)
    avatar_content_type: Mapped[str | None] = mapped_column(String(30))
    avatar_updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class Society(Base):
    __tablename__ = "societies"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    # Day of month (1-28) monthly maintenance is due.
    maintenance_due_day: Mapped[int] = mapped_column(
        nullable=False, default=10, server_default="10"
    )
    # First month monthly bills are generated for. NULL = billing not set up yet.
    billing_started_on: Mapped[date | None] = mapped_column(Date)

    flats: Mapped[list["Flat"]] = relationship(back_populates="society")


class Flat(Base):
    __tablename__ = "flats"
    __table_args__ = (
        UniqueConstraint("society_id", "flat_number", name="uq_flats_society_number"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(
        ForeignKey("societies.id"), nullable=False, index=True
    )
    flat_number: Mapped[str] = mapped_column(String(20), nullable=False)
    # '1RK' | '1BHK' | '2BHK' (see billing_service.FLAT_TYPES); NULL = not set.
    flat_type: Mapped[str | None] = mapped_column(String(10))

    society: Mapped[Society] = relationship(back_populates="flats")
    memberships: Mapped[list["FlatMembership"]] = relationship(back_populates="flat")


class FlatMembership(Base):
    """Time-bounded link between a user and a flat.

    kind = 'owner' | 'tenant'
    is_resident = True when the person actually lives there (can approve
    guests). A non-resident owner has kind='owner', is_resident=False.
    A membership is *current* when start_date <= today and
    (end_date is null or end_date >= today).
    """

    __tablename__ = "flat_memberships"
    __table_args__ = (
        CheckConstraint("kind in ('owner','tenant')", name="ck_flat_memberships_kind"),
        CheckConstraint(
            "end_date is null or end_date >= start_date",
            name="ck_flat_memberships_dates",
        ),
        Index("ix_flat_memberships_user", "user_id"),
        Index("ix_flat_memberships_flat", "flat_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    flat_id: Mapped[int] = mapped_column(ForeignKey("flats.id"), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id"), nullable=False
    )
    kind: Mapped[str] = mapped_column(String(10), nullable=False)
    is_resident: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    start_date: Mapped[date] = mapped_column(
        Date, nullable=False, server_default=func.current_date()
    )
    end_date: Mapped[date | None] = mapped_column(Date)

    flat: Mapped[Flat] = relationship(back_populates="memberships")
    user: Mapped[User] = relationship()


class SocietyAdminMembership(Base):
    """Secretary privileges, scoped to one society and revocable."""

    __tablename__ = "society_admin_memberships"
    __table_args__ = (
        Index(
            "uq_admin_active",
            "society_id",
            "user_id",
            unique=True,
            postgresql_where=text("revoked_at is null"),
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(ForeignKey("societies.id"), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    granted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class GuardMembership(Base):
    """Guard privileges, scoped to one society and revocable."""

    __tablename__ = "guard_memberships"
    __table_args__ = (
        Index(
            "uq_guard_active",
            "society_id",
            "user_id",
            unique=True,
            postgresql_where=text("revoked_at is null"),
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(ForeignKey("societies.id"), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    granted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class AuditEvent(Base):
    __tablename__ = "audit_events"
    __table_args__ = (Index("ix_audit_events_resource", "resource_type", "resource_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    actor_user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"))
    society_id: Mapped[int | None] = mapped_column(ForeignKey("societies.id"))
    action: Mapped[str] = mapped_column(String(60), nullable=False)
    resource_type: Mapped[str] = mapped_column(String(40), nullable=False)
    resource_id: Mapped[str] = mapped_column(String(64), nullable=False)
    data: Mapped[dict | None] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


# --------------------------------------------------------------------------
# Billing
# --------------------------------------------------------------------------
class Charge(Base):
    """A payable amount for a flat.

    `responsible_user_id` is a SNAPSHOT taken at creation: it never changes
    if occupancy changes later. Outstanding balance is derived from
    payment_allocations, never stored.
    """

    __tablename__ = "charges"
    __table_args__ = (
        CheckConstraint("amount_paise > 0", name="ck_charges_amount_positive"),
        CheckConstraint(
            "charge_type in ('maintenance','festival','repair','late_fee')",
            name="ck_charges_type",
        ),
        CheckConstraint("late_fee_paise >= 0", name="ck_charges_late_fee_nonneg"),
        Index("ix_charges_society", "society_id"),
        Index("ix_charges_responsible", "responsible_user_id"),
        Index("ix_charges_flat", "flat_id"),
        # One generated maintenance bill per flat per month (idempotent billing).
        Index(
            "uq_charge_maintenance_period",
            "flat_id",
            "period",
            unique=True,
            postgresql_where=text("charge_type = 'maintenance' and period is not null"),
        ),
        # At most one late fee per bill.
        Index(
            "uq_charge_late_fee_parent",
            "parent_charge_id",
            unique=True,
            postgresql_where=text("parent_charge_id is not null"),
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(ForeignKey("societies.id"), nullable=False)
    flat_id: Mapped[int] = mapped_column(ForeignKey("flats.id"), nullable=False)
    charge_type: Mapped[str] = mapped_column(String(20), nullable=False)
    title: Mapped[str] = mapped_column(String(150), nullable=False)
    amount_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    due_date: Mapped[date] = mapped_column(Date, nullable=False)
    responsible_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id"), nullable=False
    )
    # NULL = generated by the monthly billing engine, not a person.
    created_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    # First day of the billed month (generated maintenance only).
    period: Mapped[date | None] = mapped_column(Date)
    # Late fee that applies if THIS bill is overdue and unpaid. Snapshotted from
    # the plan at creation, so later plan edits never change existing bills.
    late_fee_paise: Mapped[int] = mapped_column(
        BigInteger, nullable=False, default=0, server_default="0"
    )
    # For a late-fee charge: the bill it was raised for.
    parent_charge_id: Mapped[int | None] = mapped_column(ForeignKey("charges.id"))

    allocations: Mapped[list["PaymentAllocation"]] = relationship(back_populates="charge")


class MaintenancePlan(Base):
    """Standing monthly rate + late fee for one flat type in one society.

    Set once, edited whenever the admin wants. Monthly bills copy these values
    when they are created.
    """

    __tablename__ = "maintenance_plans"
    __table_args__ = (
        UniqueConstraint("society_id", "flat_type", name="uq_plan_society_type"),
        CheckConstraint("amount_paise > 0", name="ck_plan_amount_positive"),
        CheckConstraint("penalty_paise >= 0", name="ck_plan_penalty_nonneg"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(ForeignKey("societies.id"), nullable=False)
    flat_type: Mapped[str] = mapped_column(String(10), nullable=False)
    amount_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    penalty_paise: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    updated_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"))
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


# --------------------------------------------------------------------------
# PayEngine
# --------------------------------------------------------------------------
class PaymentIntent(Base):
    """Our record of an attempt to pay, created BEFORE the gateway order."""

    __tablename__ = "payment_intents"
    __table_args__ = (
        CheckConstraint("amount_paise > 0", name="ck_intents_amount_positive"),
        CheckConstraint(
            "status in ('created','pending','paid','failed')",
            name="ck_intents_status",
        ),
        UniqueConstraint("user_id", "idempotency_key", name="uq_intents_user_idem"),
        Index("ix_intents_charge", "charge_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    charge_id: Mapped[int] = mapped_column(ForeignKey("charges.id"), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    amount_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String(64), nullable=False)
    razorpay_order_id: Mapped[str | None] = mapped_column(String(64), unique=True)
    status: Mapped[str] = mapped_column(String(10), nullable=False, default="created")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class GatewayPayment(Base):
    """A verified/captured Razorpay payment. Unique per gateway payment id,
    so client verification and webhook converge on one row."""

    __tablename__ = "gateway_payments"
    __table_args__ = (
        CheckConstraint("amount_paise > 0", name="ck_gwpay_amount_positive"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    intent_id: Mapped[int] = mapped_column(
        ForeignKey("payment_intents.id"), nullable=False, index=True
    )
    razorpay_payment_id: Mapped[str] = mapped_column(
        String(64), unique=True, nullable=False
    )
    amount_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    verified_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class WebhookEvent(Base):
    __tablename__ = "webhook_events"

    id: Mapped[int] = mapped_column(primary_key=True)
    event_id: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    event_type: Mapped[str] = mapped_column(String(60), nullable=False)
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    processed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class PaymentAllocation(Base):
    """Applies part of a verified payment to a charge.

    Unique on gateway_payment_id => a gateway payment is allocated at most
    once, even under duplicate webhooks or concurrent confirmation.
    """

    __tablename__ = "payment_allocations"
    __table_args__ = (
        CheckConstraint("amount_paise > 0", name="ck_alloc_amount_positive"),
        Index("ix_alloc_charge", "charge_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    gateway_payment_id: Mapped[int] = mapped_column(
        ForeignKey("gateway_payments.id"), unique=True, nullable=False
    )
    charge_id: Mapped[int] = mapped_column(ForeignKey("charges.id"), nullable=False)
    amount_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    charge: Mapped[Charge] = relationship(back_populates="allocations")


# --------------------------------------------------------------------------
# Onboarding, notices, push
# --------------------------------------------------------------------------
class Invite(Base):
    """Secretary pre-authorises an email for a role. Google login alone grants
    nothing; the invite is claimed on first login (email must match, and the
    email must be verified by Google)."""

    __tablename__ = "invites"
    __table_args__ = (
        CheckConstraint(
            "role in ('owner','tenant','secretary','guard')", name="ck_invites_role"
        ),
        Index("ix_invites_email", "email"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(ForeignKey("societies.id"), nullable=False)
    email: Mapped[str] = mapped_column(String(150), nullable=False)  # lower-cased
    role: Mapped[str] = mapped_column(String(10), nullable=False)
    flat_id: Mapped[int | None] = mapped_column(ForeignKey("flats.id"))
    is_resident: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    # Details the admin typed for the person; copied onto their profile when
    # they sign up (name only if they have not chosen one yet).
    full_name: Mapped[str | None] = mapped_column(String(100))
    phone: Mapped[str | None] = mapped_column(String(20))
    invited_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Notice(Base):
    __tablename__ = "notices"
    __table_args__ = (Index("ix_notices_society_created", "society_id", "created_at"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(ForeignKey("societies.id"), nullable=False)
    title: Mapped[str] = mapped_column(String(150), nullable=False)
    body: Mapped[str] = mapped_column(String(4000), nullable=False)
    pinned: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class DeviceToken(Base):
    """FCM registration token for push notifications."""

    __tablename__ = "device_tokens"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id"), nullable=False, index=True
    )
    token: Mapped[str] = mapped_column(String(512), unique=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


# --------------------------------------------------------------------------
# GateGuard (guest approvals)
# --------------------------------------------------------------------------
class GuestRequest(Base):
    """One guest visit, from approval request through check-out.

    status: pending -> approved|denied|expired -> checked_in -> checked_out.
    The decision is applied with a conditional UPDATE (WHERE status='pending')
    so the first valid response wins atomically.
    """

    __tablename__ = "guest_requests"
    __table_args__ = (
        CheckConstraint(
            "status in ('pending','approved','denied','expired',"
            "'checked_in','checked_out')",
            name="ck_guest_status",
        ),
        Index("ix_guest_flat_status", "flat_id", "status"),
        Index("ix_guest_society_status", "society_id", "status"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(ForeignKey("societies.id"), nullable=False)
    flat_id: Mapped[int] = mapped_column(ForeignKey("flats.id"), nullable=False)
    guest_name: Mapped[str] = mapped_column(String(100), nullable=False)
    guest_phone: Mapped[str | None] = mapped_column(String(20))
    purpose: Mapped[str | None] = mapped_column(String(100))
    status: Mapped[str] = mapped_column(String(12), nullable=False, default="pending")
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    decided_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"))
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    checked_in_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    checked_out_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    checked_out_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"))


# --------------------------------------------------------------------------
# Services: complaints, amenity bookings, emergency / useful contacts
# --------------------------------------------------------------------------
class Complaint(Base):
    """A resident's complaint. The admin moves it open -> in_progress -> resolved."""

    __tablename__ = "complaints"
    __table_args__ = (
        CheckConstraint("status in ('open','in_progress','resolved')", name="ck_complaints_status"),
        Index("ix_complaints_society_status", "society_id", "status"),
        Index("ix_complaints_creator", "created_by"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(ForeignKey("societies.id"), nullable=False)
    flat_id: Mapped[int | None] = mapped_column(ForeignKey("flats.id"))
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    category: Mapped[str] = mapped_column(String(20), nullable=False)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[str] = mapped_column(String(2000), nullable=False)
    status: Mapped[str] = mapped_column(String(12), nullable=False, default="open", server_default="open")
    admin_note: Mapped[str | None] = mapped_column(String(1000))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Amenity(Base):
    """A bookable common facility, e.g. the community hall."""

    __tablename__ = "amenities"
    __table_args__ = (UniqueConstraint("society_id", "name", name="uq_amenity_society_name"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(ForeignKey("societies.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str | None] = mapped_column(String(300))
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default=text('true'))


class Booking(Base):
    """A time range (society-local wall clock) of an amenity on one date. Two
    confirmed bookings of the same amenity can never overlap (exclusion
    constraint), even under races. `slot` is only a legacy label."""

    from sqlalchemy.dialects.postgresql import ExcludeConstraint

    __tablename__ = "bookings"
    __table_args__ = (
        CheckConstraint("slot in ('morning','evening')", name="ck_bookings_slot"),
        CheckConstraint("status in ('pending','confirmed','reschedule','declined','cancelled')",
            name="ck_bookings_status",
        ),
        CheckConstraint(
            "end_at > start_at AND end_at::date = start_at::date", name="ck_bookings_range"
        ),
        ExcludeConstraint(
            ("amenity_id", "="),
            (text("tsrange(start_at, end_at, '[)')"), "&&"),
            name="ex_booking_no_overlap",
            using="gist",
            where=text("status = 'confirmed'"),
        ),
        Index("ix_bookings_flat", "flat_id"),
        Index("ix_bookings_date", "booking_date"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    amenity_id: Mapped[int] = mapped_column(ForeignKey("amenities.id"), nullable=False)
    flat_id: Mapped[int] = mapped_column(ForeignKey("flats.id"), nullable=False)
    booked_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    booking_date: Mapped[date] = mapped_column(Date, nullable=False)
    slot: Mapped[str] = mapped_column(String(10), nullable=False)  # legacy label: morning | evening
    start_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)  # society-local wall clock
    end_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    purpose: Mapped[str | None] = mapped_column(String(100))
    status: Mapped[str] = mapped_column(String(10), nullable=False, default="confirmed", server_default="confirmed")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancelled_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"))
    admin_note: Mapped[str | None] = mapped_column(String(300))
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    decided_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"))


class SocietyContact(Base):
    """Emergency numbers and useful contacts, managed by the admin."""

    __tablename__ = "society_contacts"
    __table_args__ = (Index("ix_contacts_society", "society_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(ForeignKey("societies.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    label: Mapped[str | None] = mapped_column(String(60))  # e.g. "Plumber", "Security desk"
    phone: Mapped[str] = mapped_column(String(20), nullable=False)
    category: Mapped[str] = mapped_column(String(12), nullable=False, default="service")  # emergency|staff|service
    sort_order: Mapped[int] = mapped_column(nullable=False, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


# --------------------------------------------------------------------------
# Polls: collective decisions
# --------------------------------------------------------------------------
class Poll(Base):
    """A question the admin puts to the residents.

    audience: 'everyone' = every current flat member (owners AND tenants);
    'owners' = owners only. One vote per person. A poll is open until
    `closes_at` passes or the admin closes it early (`closed_at`).
    """

    __tablename__ = "polls"
    __table_args__ = (
        CheckConstraint("audience in ('everyone','owners')", name="ck_polls_audience"),
        Index("ix_polls_society_closes", "society_id", "closes_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(ForeignKey("societies.id"), nullable=False)
    title: Mapped[str] = mapped_column(String(150), nullable=False)
    description: Mapped[str | None] = mapped_column(String(1000))
    audience: Mapped[str] = mapped_column(String(10), nullable=False, default="everyone", server_default="everyone")
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    closes_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    options: Mapped[list["PollOption"]] = relationship(
        back_populates="poll", order_by="PollOption.position"
    )


class PollOption(Base):
    __tablename__ = "poll_options"
    __table_args__ = (Index("ix_poll_options_poll", "poll_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    poll_id: Mapped[int] = mapped_column(ForeignKey("polls.id"), nullable=False)
    text: Mapped[str] = mapped_column(String(120), nullable=False)
    position: Mapped[int] = mapped_column(nullable=False, default=0, server_default="0")

    poll: Mapped[Poll] = relationship(back_populates="options")


class PollVote(Base):
    """One person, one vote per poll (enforced by the unique constraint, so a
    double tap or two devices can never count twice)."""

    __tablename__ = "poll_votes"
    __table_args__ = (
        UniqueConstraint("poll_id", "user_id", name="uq_poll_vote_user"),
        Index("ix_poll_votes_option", "option_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    poll_id: Mapped[int] = mapped_column(ForeignKey("polls.id"), nullable=False)
    option_id: Mapped[int] = mapped_column(ForeignKey("poll_options.id"), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class Meeting(Base):
    """A society meeting the admin schedules. audience: 'everyone' = all current
    flat members (owners AND tenants), 'owners' = owners only."""

    __tablename__ = "meetings"
    __table_args__ = (
        CheckConstraint("audience in ('everyone','owners')", name="ck_meetings_audience"),
        Index("ix_meetings_society_time", "society_id", "scheduled_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(ForeignKey("societies.id"), nullable=False)
    title: Mapped[str] = mapped_column(String(150), nullable=False)
    agenda: Mapped[str | None] = mapped_column(String(2000))
    location: Mapped[str | None] = mapped_column(String(150))
    scheduled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    audience: Mapped[str] = mapped_column(String(10), nullable=False, default="everyone", server_default="everyone")
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


# --------------------------------------------------------------------------
# Emergency (SOS) alerts
# --------------------------------------------------------------------------
class Emergency(Base):
    """An SOS raised by a society member; stays active until resolved."""

    __tablename__ = "emergencies"
    __table_args__ = (
        CheckConstraint(
            "kind in ('fire','medical','security','other')", name="ck_emergencies_kind"
        ),
        Index("ix_emergencies_society_created", "society_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(ForeignKey("societies.id"), nullable=False)
    raised_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    flat_id: Mapped[int | None] = mapped_column(ForeignKey("flats.id"))
    kind: Mapped[str] = mapped_column(String(12), nullable=False)
    message: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    resolved_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"))


# --------------------------------------------------------------------------
# Visitor gate passes (pre-approved visitors)
# --------------------------------------------------------------------------
class GatePass(Base):
    """A resident pre-approves a visitor; the guard verifies the code at the gate."""

    __tablename__ = "gate_passes"
    __table_args__ = (
        CheckConstraint("status in ('active','used','cancelled')", name="ck_gate_pass_status"),
        CheckConstraint("valid_days between 1 and 7", name="ck_gate_pass_days"),
        Index("ix_gate_passes_flat_date", "flat_id", "visit_date"),
        Index("ix_gate_passes_society_code", "society_id", "pass_code"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    society_id: Mapped[int] = mapped_column(ForeignKey("societies.id"), nullable=False)
    flat_id: Mapped[int] = mapped_column(ForeignKey("flats.id"), nullable=False)
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), nullable=False)
    visitor_name: Mapped[str] = mapped_column(String(100), nullable=False)
    visitor_phone: Mapped[str] = mapped_column(String(20), nullable=False)
    visitor_email: Mapped[str] = mapped_column(String(150), nullable=False)
    purpose: Mapped[str | None] = mapped_column(String(100))
    vehicle_number: Mapped[str | None] = mapped_column(String(20))
    visit_date: Mapped[date] = mapped_column(Date, nullable=False)
    valid_days: Mapped[int] = mapped_column(nullable=False, default=1, server_default="1")
    valid_until_date: Mapped[date] = mapped_column(Date, nullable=False)
    pass_code: Mapped[str] = mapped_column(String(8), nullable=False, unique=True)
    status: Mapped[str] = mapped_column(String(10), nullable=False, default="active", server_default="active")
    guest_request_id: Mapped[int | None] = mapped_column(ForeignKey("guest_requests.id"))
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
