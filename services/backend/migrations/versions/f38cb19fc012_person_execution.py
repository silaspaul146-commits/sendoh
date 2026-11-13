"""Sandbox execution legs and global provider reference ownership."""
from alembic import op
import sqlalchemy as sa
revision = 'f38cb19fc012'
down_revision = 'e27ba08fb011'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('notifications', sa.Column('order_id', sa.String(36), nullable=True))
    op.create_table('person_executions',
        sa.Column('order_id', sa.String(36), sa.ForeignKey('person_orders.id'), primary_key=True),
        sa.Column('request_id', sa.String(36), sa.ForeignKey('money_requests.id')),
        sa.Column('application_hash', sa.String(64), nullable=False),
        sa.Column('state', sa.String(16), nullable=False),
        sa.Column('reason', sa.String(80)),
        sa.Column('created_at', sa.BigInteger(), nullable=False),
        sa.Column('updated_at', sa.BigInteger(), nullable=False),
        sa.CheckConstraint("state IN ('COLLECTING','FUNDED','DELIVERING','SUCCEEDED','FAILED','REVIEW')"))
    op.create_index('uq_active_request_execution', 'person_executions', ['request_id'], unique=True,
        sqlite_where=sa.text("state != 'FAILED'"), postgresql_where=sa.text("state != 'FAILED'"))
    op.create_table('person_payment_legs',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('order_id', sa.String(36), sa.ForeignKey('person_executions.order_id'), nullable=False),
        sa.Column('application_hash', sa.String(64), nullable=False),
        sa.Column('kind', sa.String(8), nullable=False),
        sa.Column('amount', sa.BigInteger(), nullable=False),
        sa.Column('method', sa.String(8), nullable=False),
        sa.Column('phone', sa.String(16), nullable=False),
        sa.Column('status', sa.String(16), nullable=False),
        sa.Column('provider_id', sa.String(120)),
        sa.Column('net', sa.Numeric(20,6)),
        sa.Column('fee', sa.Numeric(20,6)),
        sa.Column('review_reason', sa.String(80)),
        sa.Column('lease_owner', sa.String(36)),
        sa.Column('lease_until', sa.BigInteger(), nullable=False),
        sa.Column('next_check_at', sa.BigInteger(), nullable=False),
        sa.Column('attempts', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.BigInteger(), nullable=False),
        sa.UniqueConstraint('order_id','kind',name='uq_person_order_leg'),
        sa.CheckConstraint("kind IN ('COLLECT','DELIVER')"),
        sa.CheckConstraint("status IN ('PENDING','SUCCEEDED','FAILED','REFUNDED')"))
    op.create_index('ix_person_payment_legs_next_check_at', 'person_payment_legs', ['next_check_at'])
    op.create_table('provider_reference_claims',
        sa.Column('application_hash', sa.String(64), primary_key=True),
        sa.Column('provider_id', sa.String(120), primary_key=True),
        sa.Column('sendoh_reference', sa.String(36), nullable=False))
    op.execute(sa.text("INSERT INTO provider_reference_claims(application_hash,provider_id,sendoh_reference) SELECT application_hash,provider_id,id FROM provider_payments WHERE provider_id IS NOT NULL"))


def downgrade():
    if op.get_bind().execute(sa.text('SELECT COUNT(*) FROM person_executions')).scalar():
        raise RuntimeError('Execution evidence exists; preserve it before downgrade.')
    op.drop_table('person_payment_legs')
    op.drop_table('person_executions')
    op.drop_table('provider_reference_claims')
    op.drop_column('notifications', 'order_id')
