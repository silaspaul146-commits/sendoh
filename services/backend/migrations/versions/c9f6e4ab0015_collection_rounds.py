"""Recurring collections run in rounds; payments, cash and settlements belong to a round."""
from alembic import op
import sqlalchemy as sa
revision = 'c9f6e4ab0015'
down_revision = 'b8e5d3fa0014'
branch_labels = None
depends_on = None


def _round():
    return sa.Column('round', sa.Integer(), nullable=False, server_default='1')


def _checks(*checks):
    # SQLite rebuilds these tables and does not reflect unnamed checks; restate them.
    return tuple(sa.CheckConstraint(c) for c in checks) if op.get_bind().dialect.name == 'sqlite' else ()


CASH_CHECKS = ('amount > 0 AND amount <= 1000000000',)
SETTLEMENT_CHECKS = ('payout_amount > 0 AND payout_amount <= 1000000000', "method IN ('MTN','ORANGE')")


def upgrade():
    op.add_column('collections', sa.Column('recurring', sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column('collections', _round())
    op.add_column('provider_payments', _round())
    with op.batch_alter_table('cash_records', table_args=_checks(*CASH_CHECKS)) as b:
        b.add_column(_round())
        b.drop_constraint('uq_cash_participant', type_='unique')
        b.create_unique_constraint('uq_cash_participant_round', ['participant_id', 'round'])
    with op.batch_alter_table('settlements', table_args=_checks(*SETTLEMENT_CHECKS)) as b:
        b.add_column(_round())
        b.drop_constraint('uq_settlement_collection', type_='unique')
        b.create_unique_constraint('uq_settlement_round', ['collection_id', 'round'])


def downgrade():
    bind = op.get_bind()
    if bind.execute(sa.text('SELECT COUNT(*) FROM collections WHERE round > 1')).scalar():
        raise RuntimeError('Later rounds exist; archive and review before downgrade.')
    with op.batch_alter_table('settlements', table_args=_checks(*SETTLEMENT_CHECKS)) as b:
        b.drop_constraint('uq_settlement_round', type_='unique')
        b.create_unique_constraint('uq_settlement_collection', ['collection_id'])
        b.drop_column('round')
    with op.batch_alter_table('cash_records', table_args=_checks(*CASH_CHECKS)) as b:
        b.drop_constraint('uq_cash_participant_round', type_='unique')
        b.create_unique_constraint('uq_cash_participant', ['participant_id'])
        b.drop_column('round')
    with op.batch_alter_table('provider_payments') as b:
        b.drop_column('round')
    with op.batch_alter_table('collections', table_args=_checks(
            "(mode = 'ANY_AMOUNT' AND expected_amount IS NULL) OR (mode != 'ANY_AMOUNT' AND expected_amount IS NOT NULL)",
            "currency = 'XAF'", "mode IN ('ANY_AMOUNT', 'EXPECTED_TOTAL', 'MINIMUM_TOTAL')",
            'expected_amount IS NULL OR expected_amount > 0', 'target_amount IS NULL OR target_amount > 0')) as b:
        b.drop_column('round')
        b.drop_column('recurring')
