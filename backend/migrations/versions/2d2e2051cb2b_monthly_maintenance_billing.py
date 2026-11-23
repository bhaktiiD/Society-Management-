"""monthly maintenance billing

Revision ID: 2d2e2051cb2b
Revises: 4457cb94a442
Create Date: 2026-11-22 20:33:24.011178

Adds: flat types, per-type standing maintenance plans, society due day, and the
charge fields the monthly billing engine needs (period, snapshotted late fee,
late-fee parent link). Legacy apartments/residents tables are intentionally kept.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '2d2e2051cb2b'
down_revision: Union[str, Sequence[str], None] = '4457cb94a442'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('maintenance_plans',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('society_id', sa.Integer(), nullable=False),
    sa.Column('flat_type', sa.String(length=10), nullable=False),
    sa.Column('amount_paise', sa.BigInteger(), nullable=False),
    sa.Column('penalty_paise', sa.BigInteger(), nullable=False),
    sa.Column('updated_by', sa.UUID(), nullable=True),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint('amount_paise > 0', name='ck_plan_amount_positive'),
    sa.CheckConstraint('penalty_paise >= 0', name='ck_plan_penalty_nonneg'),
    sa.ForeignKeyConstraint(['society_id'], ['societies.id'], ),
    sa.ForeignKeyConstraint(['updated_by'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('society_id', 'flat_type', name='uq_plan_society_type')
    )

    op.add_column('flats', sa.Column('flat_type', sa.String(length=10), nullable=True))
    op.add_column('societies', sa.Column('maintenance_due_day', sa.Integer(), server_default='10', nullable=False))
    op.add_column('societies', sa.Column('billing_started_on', sa.Date(), nullable=True))

    op.add_column('charges', sa.Column('period', sa.Date(), nullable=True))
    op.add_column('charges', sa.Column('late_fee_paise', sa.BigInteger(), server_default='0', nullable=False))
    op.add_column('charges', sa.Column('parent_charge_id', sa.Integer(), nullable=True))
    op.alter_column('charges', 'created_by', existing_type=sa.UUID(), nullable=True)
    op.create_foreign_key('fk_charges_parent_charge', 'charges', 'charges', ['parent_charge_id'], ['id'])
    op.drop_constraint('ck_charges_type', 'charges', type_='check')
    op.create_check_constraint(
        'ck_charges_type', 'charges',
        "charge_type in ('maintenance','festival','repair','late_fee')",
    )
    op.create_check_constraint('ck_charges_late_fee_nonneg', 'charges', 'late_fee_paise >= 0')
    op.create_index(
        'uq_charge_maintenance_period', 'charges', ['flat_id', 'period'], unique=True,
        postgresql_where=sa.text("charge_type = 'maintenance' and period is not null"),
    )
    op.create_index(
        'uq_charge_late_fee_parent', 'charges', ['parent_charge_id'], unique=True,
        postgresql_where=sa.text('parent_charge_id is not null'),
    )


def downgrade() -> None:
    op.drop_index('uq_charge_late_fee_parent', table_name='charges',
                  postgresql_where=sa.text('parent_charge_id is not null'))
    op.drop_index('uq_charge_maintenance_period', table_name='charges',
                  postgresql_where=sa.text("charge_type = 'maintenance' and period is not null"))
    op.drop_constraint('ck_charges_late_fee_nonneg', 'charges', type_='check')
    op.drop_constraint('ck_charges_type', 'charges', type_='check')
    # Late fees cannot exist in the old schema.
    op.execute("delete from charges where charge_type = 'late_fee'")
    op.create_check_constraint(
        'ck_charges_type', 'charges', "charge_type in ('maintenance','festival','repair')"
    )
    op.drop_constraint('fk_charges_parent_charge', 'charges', type_='foreignkey')
    op.execute("update charges set created_by = (select id from users limit 1) where created_by is null")
    op.alter_column('charges', 'created_by', existing_type=sa.UUID(), nullable=False)
    op.drop_column('charges', 'parent_charge_id')
    op.drop_column('charges', 'late_fee_paise')
    op.drop_column('charges', 'period')
    op.drop_column('societies', 'billing_started_on')
    op.drop_column('societies', 'maintenance_due_day')
    op.drop_column('flats', 'flat_type')
    op.drop_table('maintenance_plans')
