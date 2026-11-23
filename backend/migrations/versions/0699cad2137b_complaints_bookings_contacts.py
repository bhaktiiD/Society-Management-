"""complaints bookings contacts

Revision ID: 0699cad2137b
Revises: 2d2e2051cb2b
Create Date: 2026-11-22 21:00:00

Adds complaints, amenities + bookings (with a partial unique index that makes
double-booking impossible), and society contacts. Purely additive.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0699cad2137b'
down_revision: Union[str, Sequence[str], None] = '2d2e2051cb2b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('complaints',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('society_id', sa.Integer(), nullable=False),
    sa.Column('flat_id', sa.Integer(), nullable=True),
    sa.Column('created_by', sa.UUID(), nullable=False),
    sa.Column('category', sa.String(length=20), nullable=False),
    sa.Column('title', sa.String(length=120), nullable=False),
    sa.Column('description', sa.String(length=2000), nullable=False),
    sa.Column('status', sa.String(length=12), server_default='open', nullable=False),
    sa.Column('admin_note', sa.String(length=1000), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('resolved_at', sa.DateTime(timezone=True), nullable=True),
    sa.CheckConstraint("status in ('open','in_progress','resolved')", name='ck_complaints_status'),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['flat_id'], ['flats.id'], ),
    sa.ForeignKeyConstraint(['society_id'], ['societies.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_complaints_society_status', 'complaints', ['society_id', 'status'], unique=False)
    op.create_index('ix_complaints_creator', 'complaints', ['created_by'], unique=False)

    op.create_table('amenities',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('society_id', sa.Integer(), nullable=False),
    sa.Column('name', sa.String(length=100), nullable=False),
    sa.Column('description', sa.String(length=300), nullable=True),
    sa.Column('active', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.ForeignKeyConstraint(['society_id'], ['societies.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('society_id', 'name', name='uq_amenity_society_name')
    )

    op.create_table('bookings',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('amenity_id', sa.Integer(), nullable=False),
    sa.Column('flat_id', sa.Integer(), nullable=False),
    sa.Column('booked_by', sa.UUID(), nullable=False),
    sa.Column('booking_date', sa.Date(), nullable=False),
    sa.Column('slot', sa.String(length=10), nullable=False),
    sa.Column('purpose', sa.String(length=100), nullable=True),
    sa.Column('status', sa.String(length=10), server_default='confirmed', nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('cancelled_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('cancelled_by', sa.UUID(), nullable=True),
    sa.CheckConstraint("slot in ('morning','evening')", name='ck_bookings_slot'),
    sa.CheckConstraint("status in ('confirmed','cancelled')", name='ck_bookings_status'),
    sa.ForeignKeyConstraint(['amenity_id'], ['amenities.id'], ),
    sa.ForeignKeyConstraint(['booked_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['cancelled_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['flat_id'], ['flats.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_bookings_flat', 'bookings', ['flat_id'], unique=False)
    op.create_index('ix_bookings_date', 'bookings', ['booking_date'], unique=False)
    op.create_index(
        'uq_booking_slot_confirmed', 'bookings', ['amenity_id', 'booking_date', 'slot'], unique=True,
        postgresql_where=sa.text("status = 'confirmed'"),
    )

    op.create_table('society_contacts',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('society_id', sa.Integer(), nullable=False),
    sa.Column('name', sa.String(length=100), nullable=False),
    sa.Column('label', sa.String(length=60), nullable=True),
    sa.Column('phone', sa.String(length=20), nullable=False),
    sa.Column('category', sa.String(length=12), nullable=False),
    sa.Column('sort_order', sa.Integer(), server_default='0', nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['society_id'], ['societies.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_contacts_society', 'society_contacts', ['society_id'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_contacts_society', table_name='society_contacts')
    op.drop_table('society_contacts')
    op.drop_index('uq_booking_slot_confirmed', table_name='bookings',
                  postgresql_where=sa.text("status = 'confirmed'"))
    op.drop_index('ix_bookings_date', table_name='bookings')
    op.drop_index('ix_bookings_flat', table_name='bookings')
    op.drop_table('bookings')
    op.drop_table('amenities')
    op.drop_index('ix_complaints_creator', table_name='complaints')
    op.drop_index('ix_complaints_society_status', table_name='complaints')
    op.drop_table('complaints')
