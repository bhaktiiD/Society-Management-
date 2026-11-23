"""Seed a demo society with invites (safe to re-run).

Demo accounts are invited by email. Each person gets their role the first time
they sign in. Create the matching users in Supabase (Authentication > Users >
Add user, "Auto Confirm User" ticked) and they land straight in the right role.

Usage:
    python seed_data.py
"""
import sys

from database import SessionLocal
from models import Flat, Invite, Society

SOCIETY = "Green Valley Apartments"
FLATS = ["A-101", "A-102", "A-103"]

# (email, role, flat, lives_there)
# Only the admin is pre-registered. The admin registers everyone else in the app.
DEMO = [
    ("dhavulkarbhakti030@gmail.com", "secretary", None, False),
]


def main(extra_secretaries):
    db = SessionLocal()
    try:
        society = db.query(Society).filter_by(name=SOCIETY).first()
        if society is None:
            society = Society(name=SOCIETY)
            db.add(society)
            db.flush()

        flats = {}
        for number in FLATS:
            flat = db.query(Flat).filter_by(society_id=society.id, flat_number=number).first()
            if flat is None:
                flat = Flat(society_id=society.id, flat_number=number)
                db.add(flat)
                db.flush()
            flats[number] = flat

        rows = list(DEMO) + [(e.lower(), "secretary", None, False) for e in extra_secretaries]
        added = 0
        for email, role, flat_number, lives in rows:
            flat_id = flats[flat_number].id if flat_number else None
            exists = db.query(Invite).filter_by(
                society_id=society.id, email=email, role=role, flat_id=flat_id
            ).first()
            if exists:
                continue
            db.add(Invite(society_id=society.id, email=email, role=role,
                          flat_id=flat_id, is_resident=lives))
            added += 1

        db.commit()
        print(f"{SOCIETY}: society id {society.id}, {len(flats)} flats, {added} new invites")
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    main(sys.argv[1:])
