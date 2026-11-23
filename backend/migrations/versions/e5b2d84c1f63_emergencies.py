"""emergencies

Revision ID: e5b2d84c1f63
Revises: a7c3e91b5d20
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'e5b2d84c1f63'
down_revision: Union[str, Sequence[str], None] = 'a7c3e91b5d20'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'emergencies',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('society_id', sa.Integer(), sa.ForeignKey('societies.id'), nullable=False),
        sa.Column('raised_by', sa.UUID(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('flat_id', sa.Integer(), sa.ForeignKey('flats.id'), nullable=True),
        sa.Column('kind', sa.String(length=12), nullable=False),
        sa.Column('message', sa.String(length=200), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('resolved_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('resolved_by', sa.UUID(), sa.ForeignKey('users.id'), nullable=True),
        sa.CheckConstraint("kind in ('fire','medical','security','other')", name='ck_emergencies_kind'),
    )
    op.create_index('ix_emergencies_society_created', 'emergencies', ['society_id', 'created_at'])


def downgrade() -> None:
    op.drop_index('ix_emergencies_society_created', table_name='emergencies')
    op.drop_table('emergencies')
