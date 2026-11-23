"""invite details

Revision ID: fc6f0392da5a
Revises: 0699cad2137b
Create Date: 2026-11-22 22:30:00

Registrations now carry the person's name and phone (typed by the admin), which
are copied onto their profile when they sign up. Purely additive.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'fc6f0392da5a'
down_revision: Union[str, Sequence[str], None] = '0699cad2137b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('invites', sa.Column('full_name', sa.String(length=100), nullable=True))
    op.add_column('invites', sa.Column('phone', sa.String(length=20), nullable=True))


def downgrade() -> None:
    op.drop_column('invites', 'phone')
    op.drop_column('invites', 'full_name')
