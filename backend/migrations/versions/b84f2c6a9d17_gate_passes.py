"""gate passes

Revision ID: b84f2c6a9d17
Revises: e5b2d84c1f63
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'b84f2c6a9d17'
down_revision: Union[str, Sequence[str], None] = 'e5b2d84c1f63'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'gate_passes',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('society_id', sa.Integer(), sa.ForeignKey('societies.id'), nullable=False),
        sa.Column('flat_id', sa.Integer(), sa.ForeignKey('flats.id'), nullable=False),
        sa.Column('created_by', sa.UUID(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('visitor_name', sa.String(length=100), nullable=False),
        sa.Column('visitor_phone', sa.String(length=20), nullable=False),
        sa.Column('visitor_email', sa.String(length=150), nullable=False),
        sa.Column('purpose', sa.String(length=100), nullable=True),
        sa.Column('vehicle_number', sa.String(length=20), nullable=True),
        sa.Column('visit_date', sa.Date(), nullable=False),
        sa.Column('valid_days', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('valid_until_date', sa.Date(), nullable=False),
        sa.Column('pass_code', sa.String(length=8), nullable=False, unique=True),
        sa.Column('status', sa.String(length=10), nullable=False, server_default='active'),
        sa.Column('guest_request_id', sa.Integer(), sa.ForeignKey('guest_requests.id'), nullable=True),
        sa.Column('used_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("status in ('active','used','cancelled')", name='ck_gate_pass_status'),
        sa.CheckConstraint("valid_days between 1 and 7", name='ck_gate_pass_days'),
    )
    op.create_index('ix_gate_passes_flat_date', 'gate_passes', ['flat_id', 'visit_date'])
    op.create_index('ix_gate_passes_society_code', 'gate_passes', ['society_id', 'pass_code'])


def downgrade() -> None:
    op.drop_index('ix_gate_passes_society_code', table_name='gate_passes')
    op.drop_index('ix_gate_passes_flat_date', table_name='gate_passes')
    op.drop_table('gate_passes')
