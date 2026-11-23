"""booking approval workflow

Revision ID: a7c3e91b5d20
Revises: d469f76b7cdf
Create Date: 2026-11-23 10:00:00

Bookings now start as 'pending' and are decided by the admin. Adds statuses
pending/reschedule/declined plus admin_note, decided_at, decided_by.
Additive; the partial unique index (confirmed only) is untouched.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'a7c3e91b5d20'
down_revision: Union[str, Sequence[str], None] = 'd469f76b7cdf'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_constraint('ck_bookings_status', 'bookings', type_='check')
    op.create_check_constraint(
        'ck_bookings_status', 'bookings',
        "status in ('pending','confirmed','reschedule','declined','cancelled')",
    )
    op.add_column('bookings', sa.Column('admin_note', sa.String(length=300), nullable=True))
    op.add_column('bookings', sa.Column('decided_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('bookings', sa.Column('decided_by', sa.UUID(), nullable=True))
    op.create_foreign_key('fk_bookings_decided_by', 'bookings', 'users', ['decided_by'], ['id'])


def downgrade() -> None:
    op.drop_constraint('fk_bookings_decided_by', 'bookings', type_='foreignkey')
    op.drop_column('bookings', 'decided_by')
    op.drop_column('bookings', 'decided_at')
    op.drop_column('bookings', 'admin_note')
    op.execute(
        "UPDATE bookings SET status = 'cancelled' "
        "WHERE status IN ('pending','reschedule','declined')"
    )
    op.drop_constraint('ck_bookings_status', 'bookings', type_='check')
    op.create_check_constraint(
        'ck_bookings_status', 'bookings', "status in ('confirmed','cancelled')"
    )
