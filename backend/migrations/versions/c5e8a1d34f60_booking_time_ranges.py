"""booking custom time ranges

Revision ID: c5e8a1d34f60
Revises: b84f2c6a9d17
Create Date: 2026-11-23 14:00:00

Adds start_at/end_at (society-local wall clock, no tz), backfilled from
booking_date + slot (morning 08:00-13:00, evening 16:00-22:00). Replaces the
slot unique index with an exclusion constraint on overlapping confirmed ranges.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'c5e8a1d34f60'
down_revision: Union[str, Sequence[str], None] = 'b84f2c6a9d17'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS btree_gist")
    op.add_column('bookings', sa.Column('start_at', sa.DateTime(), nullable=True))
    op.add_column('bookings', sa.Column('end_at', sa.DateTime(), nullable=True))
    op.execute(
        "UPDATE bookings SET "
        "start_at = booking_date + CASE WHEN slot = 'morning' THEN time '08:00' ELSE time '16:00' END, "
        "end_at = booking_date + CASE WHEN slot = 'morning' THEN time '13:00' ELSE time '22:00' END"
    )
    op.alter_column('bookings', 'start_at', nullable=False)
    op.alter_column('bookings', 'end_at', nullable=False)
    op.drop_index('uq_booking_slot_confirmed', table_name='bookings')
    op.create_check_constraint(
        'ck_bookings_range', 'bookings',
        "end_at > start_at AND end_at::date = start_at::date",
    )
    op.execute(
        "ALTER TABLE bookings ADD CONSTRAINT ex_booking_no_overlap "
        "EXCLUDE USING gist (amenity_id WITH =, tsrange(start_at, end_at, '[)') WITH &&) "
        "WHERE (status = 'confirmed')"
    )


def downgrade() -> None:
    op.drop_constraint('ex_booking_no_overlap', 'bookings', type_='unique')
    op.drop_constraint('ck_bookings_range', 'bookings', type_='check')
    # Best effort: ranges may share a slot label; cancel later duplicates so the
    # old unique index can be rebuilt.
    op.execute(
        "UPDATE bookings SET status = 'cancelled' WHERE id IN ("
        "SELECT id FROM (SELECT id, row_number() OVER ("
        "PARTITION BY amenity_id, booking_date, slot ORDER BY start_at, id) rn "
        "FROM bookings WHERE status = 'confirmed') t WHERE rn > 1)"
    )
    op.create_index(
        'uq_booking_slot_confirmed', 'bookings',
        ['amenity_id', 'booking_date', 'slot'], unique=True,
        postgresql_where=sa.text("status = 'confirmed'"),
    )
    op.drop_column('bookings', 'end_at')
    op.drop_column('bookings', 'start_at')
