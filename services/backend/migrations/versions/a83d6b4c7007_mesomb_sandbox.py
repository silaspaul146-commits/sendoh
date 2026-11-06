"""MeSomb sandbox attempts and verified event evidence."""
from alembic import op
import sqlalchemy as sa
revision = 'a83d6b4c7007'
down_revision = 'f72c5a3b6006'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('provider_payments',
        sa.Column('id', sa.String(length=36), nullable=False, primary_key=True),
        sa.Column('collection_id', sa.String(length=36), sa.ForeignKey('collections.id'), nullable=False),
        sa.Column('participant_id', sa.String(length=36), sa.ForeignKey('participants.id'), nullable=False),
        sa.Column('payer_id', sa.String(length=36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('beneficiary_id', sa.String(length=36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('request_key', sa.String(length=120), nullable=False),
        sa.Column('fingerprint', sa.String(length=64), nullable=False),
        sa.Column('application_hash', sa.String(length=64), nullable=False),
        sa.Column('mode', sa.String(length=12), nullable=False),
        sa.Column('amount', sa.BigInteger(), nullable=False),
        sa.Column('method', sa.String(length=8), nullable=False),
        sa.Column('payer_phone', sa.String(length=16), nullable=False),
        sa.Column('status', sa.String(length=12), nullable=False),
        sa.Column('provider_id', sa.String(length=120), nullable=True),
        sa.Column('provider_status', sa.String(length=40), nullable=True),
        sa.Column('review_reason', sa.String(length=80), nullable=True),
        sa.Column('attempts', sa.Integer(), nullable=False),
        sa.Column('next_check_at', sa.BigInteger(), nullable=False),
        sa.Column('lease_until', sa.BigInteger(), nullable=False),
        sa.Column('lease_owner', sa.String(length=36), nullable=True),
        sa.Column('created_at', sa.BigInteger(), nullable=False),
        sa.Column('updated_at', sa.BigInteger(), nullable=False),
        sa.UniqueConstraint('application_hash', 'provider_id', name='uq_provider_transaction'),
        sa.CheckConstraint("method IN ('MTN','ORANGE')"),
        sa.CheckConstraint("mode = 'SANDBOX'"),
        sa.UniqueConstraint('payer_id', 'request_key', name='uq_provider_payment_request'),
        sa.CheckConstraint("status IN ('PENDING','SUCCEEDED','FAILED','REFUNDED')"),
        sa.CheckConstraint('amount > 0 AND amount <= 1000000000'),
    )
    op.create_index('ix_provider_payments_payer_id', 'provider_payments', ['payer_id'])
    op.create_index('ix_provider_payments_next_check_at', 'provider_payments', ['next_check_at'])
    op.create_index('ix_provider_payments_collection_id', 'provider_payments', ['collection_id'])
    op.create_index('uq_pending_provider_collection', 'provider_payments', ['payer_id', 'collection_id'],
                    unique=True, sqlite_where=sa.text("status = 'PENDING'"),
                    postgresql_where=sa.text("status = 'PENDING'"))
    op.create_table('provider_payment_events',
        sa.Column('id', sa.String(length=36), nullable=False, primary_key=True),
        sa.Column('payment_id', sa.String(length=36), sa.ForeignKey('provider_payments.id'), nullable=False),
        sa.Column('status', sa.String(length=12), nullable=False),
        sa.Column('created_at', sa.BigInteger(), nullable=False),
        sa.UniqueConstraint('payment_id', 'status', name='uq_provider_payment_effect'),
    )
    op.create_index('ix_provider_payment_events_payment_id', 'provider_payment_events', ['payment_id'])
    op.create_table('mesomb_webhooks',
        sa.Column('event_id', sa.String(length=160), nullable=False, primary_key=True),
        sa.Column('body_hash', sa.String(length=64), nullable=False),
        sa.Column('event_type', sa.String(length=120), nullable=False),
        sa.Column('received_at', sa.BigInteger(), nullable=False),
    )


def downgrade():
    for name in ('provider_payments', 'mesomb_webhooks'):
        if op.get_bind().execute(sa.text('SELECT COUNT(*) FROM ' + name)).scalar():
            raise RuntimeError('Payment evidence exists; archive and review before downgrade.')
    op.drop_table('provider_payment_events')
    op.drop_table('mesomb_webhooks')
    op.drop_table('provider_payments')
