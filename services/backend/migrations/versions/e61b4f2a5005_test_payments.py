"""Separate persisted sandbox payment ledger."""
from alembic import op
import sqlalchemy as sa
revision = 'e61b4f2a5005'
down_revision = 'd50a3e1f4004'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('test_payments',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('collection_id', sa.String(36), sa.ForeignKey('collections.id'), nullable=False),
        sa.Column('participant_id', sa.String(36), sa.ForeignKey('participants.id'), nullable=False),
        sa.Column('payer_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('payer_name', sa.String(120), nullable=False),
        sa.Column('collection_name', sa.String(120), nullable=False),
        sa.Column('request_key', sa.String(120), nullable=False),
        sa.Column('fingerprint', sa.String(64), nullable=False),
        sa.Column('amount', sa.BigInteger(), nullable=False),
        sa.Column('method', sa.String(8), nullable=False),
        sa.Column('note', sa.String(200), nullable=False),
        sa.Column('status', sa.String(12), nullable=False),
        sa.Column('created_at', sa.BigInteger(), nullable=False),
        sa.Column('completed_at', sa.BigInteger(), nullable=True),
        sa.UniqueConstraint('payer_id', 'request_key', name='uq_test_payment_request'),
        sa.CheckConstraint('amount > 0 AND amount <= 1000000000000'),
        sa.CheckConstraint("status IN ('PENDING','SUCCEEDED','FAILED','CANCELLED')"),
        sa.CheckConstraint("method IN ('MTN','ORANGE')"))
    for col in ('collection_id', 'participant_id', 'payer_id'):
        op.create_index('ix_test_payments_' + col, 'test_payments', [col])


def downgrade():
    op.drop_table('test_payments')
