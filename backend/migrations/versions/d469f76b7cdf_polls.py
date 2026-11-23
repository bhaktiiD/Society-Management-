"""polls, meetings, profile photo

Revision ID: d469f76b7cdf
Revises: fc6f0392da5a
Create Date: 2026-11-22 23:30:00

Adds polls (+ options + one-vote-per-person votes), meetings, and profile photo
columns on users. Purely additive.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'd469f76b7cdf'
down_revision: Union[str, Sequence[str], None] = 'fc6f0392da5a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('polls',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('society_id', sa.Integer(), nullable=False),
    sa.Column('title', sa.String(length=150), nullable=False),
    sa.Column('description', sa.String(length=1000), nullable=True),
    sa.Column('audience', sa.String(length=10), server_default='everyone', nullable=False),
    sa.Column('created_by', sa.UUID(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('closes_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('closed_at', sa.DateTime(timezone=True), nullable=True),
    sa.CheckConstraint("audience in ('everyone','owners')", name='ck_polls_audience'),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['society_id'], ['societies.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_polls_society_closes', 'polls', ['society_id', 'closes_at'], unique=False)

    op.create_table('poll_options',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('poll_id', sa.Integer(), nullable=False),
    sa.Column('text', sa.String(length=120), nullable=False),
    sa.Column('position', sa.Integer(), server_default='0', nullable=False),
    sa.ForeignKeyConstraint(['poll_id'], ['polls.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_poll_options_poll', 'poll_options', ['poll_id'], unique=False)

    op.create_table('poll_votes',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('poll_id', sa.Integer(), nullable=False),
    sa.Column('option_id', sa.Integer(), nullable=False),
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['option_id'], ['poll_options.id'], ),
    sa.ForeignKeyConstraint(['poll_id'], ['polls.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('poll_id', 'user_id', name='uq_poll_vote_user')
    )
    op.create_index('ix_poll_votes_option', 'poll_votes', ['option_id'], unique=False)

    op.create_table('meetings',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('society_id', sa.Integer(), nullable=False),
    sa.Column('title', sa.String(length=150), nullable=False),
    sa.Column('agenda', sa.String(length=2000), nullable=True),
    sa.Column('location', sa.String(length=150), nullable=True),
    sa.Column('scheduled_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('audience', sa.String(length=10), server_default='everyone', nullable=False),
    sa.Column('created_by', sa.UUID(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('cancelled_at', sa.DateTime(timezone=True), nullable=True),
    sa.CheckConstraint("audience in ('everyone','owners')", name='ck_meetings_audience'),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['society_id'], ['societies.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_meetings_society_time', 'meetings', ['society_id', 'scheduled_at'], unique=False)

    op.add_column('users', sa.Column('avatar', sa.LargeBinary(), nullable=True))
    op.add_column('users', sa.Column('avatar_content_type', sa.String(length=30), nullable=True))
    op.add_column('users', sa.Column('avatar_updated_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'avatar_updated_at')
    op.drop_column('users', 'avatar_content_type')
    op.drop_column('users', 'avatar')
    op.drop_index('ix_meetings_society_time', table_name='meetings')
    op.drop_table('meetings')
    op.drop_index('ix_poll_votes_option', table_name='poll_votes')
    op.drop_table('poll_votes')
    op.drop_index('ix_poll_options_poll', table_name='poll_options')
    op.drop_table('poll_options')
    op.drop_index('ix_polls_society_closes', table_name='polls')
    op.drop_table('polls')
