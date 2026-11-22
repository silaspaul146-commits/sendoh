"""Close and settle: collection lifecycle, cash records, settlement payouts."""
from alembic import op
import sqlalchemy as sa
revision = 'b8e5d3fa0014'
down_revision = 'a7d4c2e9b013'
branch_labels = None
depends_on = None

STATUS = "status IN ('DRAFT', 'ACTIVE', 'CLOSED', 'SETTLED')"
OLD_STATUS = "status IN ('DRAFT', 'ACTIVE')"


def _collection_checks():
    # SQLite rebuilds the table and does not reflect unnamed checks; restate them.
    return (sa.CheckConstraint("(mode = 'ANY_AMOUNT' AND expected_amount IS NULL) OR (mode != 'ANY_AMOUNT' AND expected_amount IS NOT NULL)"),
            sa.CheckConstraint("currency = 'XAF'"),
            sa.CheckConstraint("mode IN ('ANY_AMOUNT', 'EXPECTED_TOTAL', 'MINIMUM_TOTAL')"),
            sa.CheckConstraint('expected_amount IS NULL OR expected_amount > 0'),
            sa.CheckConstraint('target_amount IS NULL OR target_amount > 0'))


def _status(check):
    bind = op.get_bind()
    if bind.dialect.name == 'sqlite':
        # SQLite reflection keeps NAMED checks but drops unnamed ones on rebuild.
        ddl = bind.execute(sa.text("SELECT sql FROM sqlite_master WHERE name = 'collections'")).scalar() or ''
        with op.batch_alter_table('collections', recreate='always', table_args=_collection_checks()) as b:
            if 'ck_collection_status' in ddl:
                b.drop_constraint('ck_collection_status', type_='check')
            b.create_check_constraint('ck_collection_status', check)
    else:
        # PostgreSQL auto-named the original unnamed check collections_status_check.
        op.execute('ALTER TABLE collections DROP CONSTRAINT IF EXISTS collections_status_check')
        op.execute('ALTER TABLE collections DROP CONSTRAINT IF EXISTS ck_collection_status')
        op.create_check_constraint('ck_collection_status', 'collections', check)


def upgrade():
    _status(STATUS)
    op.add_column('notifications', sa.Column('settlement_id', sa.String(36), nullable=True))
    op.create_table('cash_records',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('collection_id', sa.String(36), sa.ForeignKey('collections.id'), nullable=False),
        sa.Column('participant_id', sa.String(36), sa.ForeignKey('participants.id'), nullable=False),
        sa.Column('amount', sa.BigInteger(), nullable=False),
        sa.Column('recorded_by', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('updated_at', sa.BigInteger(), nullable=False),
        sa.Column('flagged_at', sa.BigInteger(), nullable=True),
        sa.UniqueConstraint('participant_id', name='uq_cash_participant'),
        sa.CheckConstraint('amount > 0 AND amount <= 1000000000'))
    op.create_index('ix_cash_records_collection_id', 'cash_records', ['collection_id'])
    op.create_table('settlements',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('collection_id', sa.String(36), sa.ForeignKey('collections.id'), nullable=False),
        sa.Column('organizer_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('request_key', sa.String(120), nullable=False),
        sa.Column('destination_id', sa.String(36), sa.ForeignKey('receiving_destinations.id'), nullable=False),
        sa.Column('phone', sa.String(16), nullable=False),
        sa.Column('method', sa.String(8), nullable=False),
        sa.Column('application_hash', sa.String(64), nullable=False),
        sa.Column('policy', sa.JSON(), nullable=False),
        sa.Column('amounts', sa.JSON(), nullable=False),
        sa.Column('payout_amount', sa.BigInteger(), nullable=False),
        sa.Column('state', sa.String(12), nullable=False),
        sa.Column('payout_status', sa.String(12), nullable=False),
        sa.Column('provider_id', sa.String(120), nullable=True),
        sa.Column('review_reason', sa.String(80), nullable=True),
        sa.Column('attempts', sa.Integer(), nullable=False),
        sa.Column('next_check_at', sa.BigInteger(), nullable=False),
        sa.Column('lease_until', sa.BigInteger(), nullable=False),
        sa.Column('lease_owner', sa.String(36), nullable=True),
        sa.Column('created_at', sa.BigInteger(), nullable=False),
        sa.Column('updated_at', sa.BigInteger(), nullable=False),
        sa.UniqueConstraint('collection_id', name='uq_settlement_collection'),
        sa.UniqueConstraint('organizer_id', 'request_key', name='uq_settlement_request'),
        sa.CheckConstraint("state IN ('SENDING','DELIVERED','REVIEW')", name='ck_settlement_state'),
        sa.CheckConstraint("payout_status IN ('PENDING','SUCCEEDED','FAILED','REFUNDED')", name='ck_settlement_payout_status'),
        sa.CheckConstraint('payout_amount > 0 AND payout_amount <= 1000000000'),
        sa.CheckConstraint("method IN ('MTN','ORANGE')"))
    op.create_index('ix_settlements_organizer_id', 'settlements', ['organizer_id'])
    op.create_index('ix_settlements_next_check_at', 'settlements', ['next_check_at'])


def downgrade():
    bind = op.get_bind()
    if (bind.execute(sa.text('SELECT COUNT(*) FROM settlements')).scalar()
            or bind.execute(sa.text('SELECT COUNT(*) FROM cash_records')).scalar()
            or bind.execute(sa.text("SELECT COUNT(*) FROM collections WHERE status IN ('CLOSED','SETTLED')")).scalar()):
        raise RuntimeError('Settlement or cash evidence exists; archive and review before downgrade.')
    op.drop_index('ix_settlements_next_check_at', 'settlements')
    op.drop_index('ix_settlements_organizer_id', 'settlements')
    op.drop_table('settlements')
    op.drop_index('ix_cash_records_collection_id', 'cash_records')
    op.drop_table('cash_records')
    op.drop_column('notifications', 'settlement_id')
    _status(OLD_STATUS)
