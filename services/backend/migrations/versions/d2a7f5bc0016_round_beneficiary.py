"""Rotating beneficiaries: who receives each round's payout."""
from alembic import op
import sqlalchemy as sa
revision = 'd2a7f5bc0016'
down_revision = 'c9f6e4ab0015'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('collections', sa.Column('beneficiary_participant_id', sa.String(36), nullable=True))
    with op.batch_alter_table('settlements', table_args=_settlement_checks()) as b:
        b.add_column(sa.Column('beneficiary_id', sa.String(36), nullable=True))
        b.create_foreign_key('fk_settlement_beneficiary', 'users', ['beneficiary_id'], ['id'])


def _sqlite():
    return op.get_bind().dialect.name == 'sqlite'


def _settlement_checks():
    # SQLite rebuilds the table and does not reflect unnamed checks; restate them.
    return (sa.CheckConstraint('payout_amount > 0 AND payout_amount <= 1000000000'),
            sa.CheckConstraint("method IN ('MTN','ORANGE')")) if _sqlite() else ()


def downgrade():
    bind = op.get_bind()
    if bind.execute(sa.text('SELECT COUNT(*) FROM settlements WHERE beneficiary_id IS NOT NULL '
                            'AND beneficiary_id != organizer_id')).scalar():
        raise RuntimeError('Payouts to members exist; archive and review before downgrade.')
    with op.batch_alter_table('settlements', table_args=_settlement_checks()) as b:
        b.drop_constraint('fk_settlement_beneficiary', type_='foreignkey')
        b.drop_column('beneficiary_id')
    collection_checks = (
        sa.CheckConstraint("(mode = 'ANY_AMOUNT' AND expected_amount IS NULL) OR (mode != 'ANY_AMOUNT' AND expected_amount IS NOT NULL)"),
        sa.CheckConstraint("currency = 'XAF'"),
        sa.CheckConstraint("mode IN ('ANY_AMOUNT', 'EXPECTED_TOTAL', 'MINIMUM_TOTAL')"),
        sa.CheckConstraint('expected_amount IS NULL OR expected_amount > 0'),
        sa.CheckConstraint('target_amount IS NULL OR target_amount > 0')) if _sqlite() else ()
    with op.batch_alter_table('collections', table_args=collection_checks) as b:
        b.drop_column('beneficiary_participant_id')
