"""Demo data so the dashboards show something real.

Creates fake residents (emails @demo.societyos, which can never sign in or clash
with real accounts), flats with types, standing maintenance rates, October and
November bills in every state, late fees on overdue unpaid bills, payments and
notices. Admin-set rates and due day are never overwritten.

    python seed_demo.py           # add demo data (skips if already present)
    python seed_demo.py --reset   # remove demo residents and everything they own
"""
import sys
import uuid
from datetime import date, datetime, timedelta, timezone

from billing_service import add_month, ensure_billing, first_of_month, month_label
from database import SessionLocal
from models import (
    Amenity,
    AuditEvent,
    Booking,
    Charge,
    Complaint,
    Flat,
    FlatMembership,
    GatewayPayment,
    MaintenancePlan,
    Notice,
    PaymentAllocation,
    PaymentIntent,
    Society,
    SocietyContact,
    User,
)

DEMO_DOMAIN = "@demo.societyos"
SOCIETY = "Green Valley Apartments"
TODAY = date.today()
START = TODAY - timedelta(days=365)

# flat -> (type, owner name, owner lives there?, tenant name or None)
FLATS = {
    "A-101": ("2BHK", "Rahul Sharma", True, None),
    "A-102": ("1BHK", "Priya Nair", False, "Arjun Mehta"),
    "A-103": ("2BHK", "Sunita Patel", True, None),
    "A-104": ("1RK", "Vikram Singh", True, None),
    "A-201": ("2BHK", "Neha Gupta", True, None),
    "A-202": ("1BHK", "Rohan Das", False, "Kavya Iyer"),
}

# type -> (monthly rate, late fee) in paise. Only used if the admin has not set one.
PLANS = {"1RK": (150000, 10000), "1BHK": (200000, 15000), "2BHK": (300000, 20000)}

# Payments already made. {month offset: {flat: paise paid}}; offset 0 = this month.
# Anything not listed is unpaid. A-104 and A-202 are the overdue defaulters.
PAID = {
    -1: {"A-101": "full", "A-102": "full", "A-103": "full", "A-201": "full", "A-202": "full"},
    0: {"A-101": "full", "A-103": "full", "A-201": "full", "A-102": 100000},
}

NOTICES = [
    ("Water tank cleaning on Sunday", "The overhead tanks will be cleaned this Sunday from 10 AM to 1 PM. "
     "Please store water in advance.", True),
    ("Diwali celebration at the clubhouse", "Join us at 7 PM on Diwali evening for sweets, lights and music. "
     "Everyone is welcome.", False),
    ("Lift maintenance on 25 Nov", "Lift B will be out of service between 2 PM and 5 PM for maintenance.", False),
    ("Parking sticker renewal", "Renew your vehicle stickers with the office before the end of the month.", False),
]


# name, label, phone, category
CONTACTS = [
    ("Police", "Emergency", "100", "emergency"),
    ("Ambulance", "Emergency", "108", "emergency"),
    ("Fire brigade", "Emergency", "101", "emergency"),
    ("Main gate security", "24 hours", "98765 00001", "staff"),
    ("Society office", "9 AM - 6 PM", "98765 00002", "staff"),
    ("Ramesh (Plumber)", "Plumbing", "98765 00003", "service"),
    ("Suresh (Electrician)", "Electrical", "98765 00004", "service"),
]

# flat, category, title, description, status, admin note
COMPLAINTS = [
    ("A-101", "lift", "Lift B stops between floors",
     "The lift in block B stopped between the 2nd and 3rd floor twice this week.", "open", None),
    ("A-103", "plumbing", "Water leakage in the corridor",
     "There is a steady leak from the ceiling in the 1st floor corridor near A-103.",
     "in_progress", "Plumber visits tomorrow morning."),
    ("A-201", "electrical", "Street light not working",
     "The street light near the car park entrance has been off for three days.",
     "resolved", "Bulb replaced on Friday."),
]

# flat, days from today, slot, purpose
BOOKINGS = [
    ("A-101", 3, "evening", "Birthday party"),
    ("A-103", 9, "morning", "Satyanarayan pooja"),
]


def email_for(name: str) -> str:
    return name.lower().replace(" ", ".") + DEMO_DOMAIN


def reset(db):
    demo_ids = [u.id for u in db.query(User).filter(User.email.like(f"%{DEMO_DOMAIN}")).all()]
    if not demo_ids:
        print("no demo data found")
        return
    charge_ids = [c.id for c in db.query(Charge).filter(Charge.responsible_user_id.in_(demo_ids))]
    intent_ids = [i.id for i in db.query(PaymentIntent).filter(PaymentIntent.charge_id.in_(charge_ids))]
    pay_ids = [p.id for p in db.query(GatewayPayment).filter(GatewayPayment.intent_id.in_(intent_ids))]
    db.query(PaymentAllocation).filter(PaymentAllocation.gateway_payment_id.in_(pay_ids)).delete(synchronize_session=False)
    db.query(GatewayPayment).filter(GatewayPayment.id.in_(pay_ids)).delete(synchronize_session=False)
    db.query(PaymentIntent).filter(PaymentIntent.id.in_(intent_ids)).delete(synchronize_session=False)
    # Late fees point at their bill, so delete them before the bills.
    db.query(Charge).filter(Charge.id.in_(charge_ids), Charge.parent_charge_id.isnot(None)).delete(synchronize_session=False)
    db.query(Charge).filter(Charge.id.in_(charge_ids)).delete(synchronize_session=False)
    db.query(Notice).filter(Notice.created_by.in_(demo_ids)).delete(synchronize_session=False)
    db.query(Complaint).filter(Complaint.created_by.in_(demo_ids)).delete(synchronize_session=False)
    db.query(Booking).filter(Booking.booked_by.in_(demo_ids)).delete(synchronize_session=False)
    db.query(AuditEvent).filter(AuditEvent.actor_user_id.in_(demo_ids)).delete(synchronize_session=False)
    db.query(FlatMembership).filter(FlatMembership.user_id.in_(demo_ids)).delete(synchronize_session=False)
    db.query(User).filter(User.id.in_(demo_ids)).delete(synchronize_session=False)
    db.commit()
    print(f"removed demo data ({len(demo_ids)} demo users and everything they own)")


def seed(db):
    if db.query(User).filter(User.email.like(f"%{DEMO_DOMAIN}")).first():
        print("demo data already present (use --reset to rebuild)")
        return

    society = db.query(Society).filter_by(name=SOCIETY).first()
    if society is None:
        society = Society(name=SOCIETY)
        db.add(society)
        db.flush()

    # Standing rates + billing start: only if the admin has not set them.
    this_month = first_of_month(TODAY)
    last_month = first_of_month(this_month - timedelta(days=1))
    if society.billing_started_on is None:
        society.billing_started_on = last_month
    for ftype, (amount, penalty) in PLANS.items():
        if not db.query(MaintenancePlan).filter_by(society_id=society.id, flat_type=ftype).first():
            db.add(MaintenancePlan(society_id=society.id, flat_type=ftype,
                                   amount_paise=amount, penalty_paise=penalty))
    db.flush()
    plans = {p.flat_type: p for p in db.query(MaintenancePlan).filter_by(society_id=society.id)}

    flats = {}
    for number, (ftype, *_rest) in FLATS.items():
        flat = db.query(Flat).filter_by(society_id=society.id, flat_number=number).first()
        if flat is None:
            flat = Flat(society_id=society.id, flat_number=number)
            db.add(flat)
            db.flush()
        if flat.flat_type is None:
            flat.flat_type = ftype
        flats[number] = flat

    admin = User(id=uuid.uuid4(), email=email_for("Demo Admin"), full_name="Demo Admin")
    db.add(admin)
    owners, tenants = {}, {}
    for number, (_t, owner_name, lives, tenant_name) in FLATS.items():
        owner = User(id=uuid.uuid4(), email=email_for(owner_name), full_name=owner_name,
                     phone="98765 4%04d" % len(owners))
        db.add(owner)
        owners[number] = owner
        db.flush()
        db.add(FlatMembership(flat_id=flats[number].id, user_id=owner.id, kind="owner",
                              is_resident=lives, start_date=START))
        if tenant_name:
            tenant = User(id=uuid.uuid4(), email=email_for(tenant_name), full_name=tenant_name,
                          phone="98765 5%04d" % len(tenants))
            db.add(tenant)
            tenants[number] = tenant
            db.flush()
            db.add(FlatMembership(flat_id=flats[number].id, user_id=tenant.id, kind="tenant",
                                  is_resident=True, start_date=START))

    counter = {"n": 0}

    def pay(c, who, paise):
        counter["n"] += 1
        n = counter["n"]
        intent = PaymentIntent(charge_id=c.id, user_id=who.id, amount_paise=paise,
                               idempotency_key=f"demo-{n:06d}", razorpay_order_id=f"order_demo_{n:06d}",
                               status="paid")
        db.add(intent)
        db.flush()
        gp = GatewayPayment(intent_id=intent.id, razorpay_payment_id=f"pay_demo_{n:06d}", amount_paise=paise)
        db.add(gp)
        db.flush()
        db.add(PaymentAllocation(gateway_payment_id=gp.id, charge_id=c.id, amount_paise=paise))

    def charge(number, who, ctype, title, amount, due, paid=0, period=None, late_fee=0):
        c = Charge(society_id=society.id, flat_id=flats[number].id, charge_type=ctype, title=title,
                   amount_paise=amount, due_date=due, responsible_user_id=who.id, created_by=admin.id,
                   period=period, late_fee_paise=late_fee)
        db.add(c)
        db.flush()
        if paid:
            pay(c, who, paid)
        return c

    # Monthly bills for last month and this month, issued on time (so the late
    # fee was snapshotted), exactly as the billing engine would have made them.
    for offset, period in ((-1, last_month), (0, this_month)):
        due = period.replace(day=society.maintenance_due_day)
        for number, owner in owners.items():
            plan = plans[FLATS[number][0]]
            paid = PAID[offset].get(number, 0)
            paid = plan.amount_paise if paid == "full" else paid
            charge(number, owner, "maintenance", f"{month_label(period)} maintenance",
                   plan.amount_paise, due, paid, period=period, late_fee=plan.penalty_paise)

    charge("A-101", owners["A-101"], "repair", "Lift repair share", 120000, TODAY + timedelta(days=9))
    charge("A-102", tenants["A-102"], "festival", "Diwali celebration", 50000, TODAY - timedelta(days=7), 50000)
    charge("A-202", tenants["A-202"], "festival", "Diwali celebration", 50000, TODAY - timedelta(days=7))

    for title, body, pinned in NOTICES:
        db.add(Notice(society_id=society.id, title=title, body=body, pinned=pinned, created_by=admin.id))

    # Emergency / useful contacts: only if the admin has not added any yet.
    if not db.query(SocietyContact).filter_by(society_id=society.id).first():
        for name, label, phone, cat in CONTACTS:
            db.add(SocietyContact(society_id=society.id, name=name, label=label, phone=phone, category=cat))

    # Complaints in every state.
    now = datetime.now(timezone.utc)
    for number, category, title, desc, status, note in COMPLAINTS:
        db.add(Complaint(
            society_id=society.id, flat_id=flats[number].id, created_by=owners[number].id,
            category=category, title=title, description=desc, status=status, admin_note=note,
            resolved_at=now if status == "resolved" else None,
        ))

    # Two upcoming hall bookings.
    hall = db.query(Amenity).filter_by(society_id=society.id, name="Community Hall").first()
    if hall is None:
        hall = Amenity(society_id=society.id, name="Community Hall",
                       description="Morning 8 AM - 1 PM, Evening 4 PM - 10 PM")
        db.add(hall)
        db.flush()
    for number, days, slot, purpose in BOOKINGS:
        db.add(Booking(amenity_id=hall.id, flat_id=flats[number].id, booked_by=owners[number].id,
                       booking_date=TODAY + timedelta(days=days), slot=slot, purpose=purpose))
    db.commit()

    # Let the real engine raise late fees for the overdue, unpaid bills.
    result = ensure_billing(db, society.id)
    n = db.query(Charge).filter_by(society_id=society.id).count()
    print(f"demo data added: {len(flats)} flats, {len(owners) + len(tenants)} residents, "
          f"{n} charges (incl. {result['late_fees_created']} late fees), {len(NOTICES)} notices")


if __name__ == "__main__":
    session = SessionLocal()
    try:
        (reset if "--reset" in sys.argv else seed)(session)
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
