"""Durable expiring fee quotes and non-dispatched person payment orders."""
from alembic import op
import sqlalchemy as sa

revision = 'e27ba08fb011'
down_revision = 'd16a9e7fa010'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('person_quotes',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('payer_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('beneficiary_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('request_id', sa.String(36), sa.ForeignKey('money_requests.id')),
        sa.Column('destination_id', sa.String(36), sa.ForeignKey('receiving_destinations.id'), nullable=False),
        sa.Column('application_hash', sa.String(64), nullable=False),
        sa.Column('policy_hash', sa.String(64), nullable=False),
        sa.Column('policy', sa.JSON(), nullable=False),
        sa.Column('amounts', sa.JSON(), nullable=False),
        sa.Column('payer_phone', sa.String(16), nullable=False),
        sa.Column('payer_method', sa.String(8), nullable=False),
        sa.Column('created_at', sa.BigInteger(), nullable=False),
        sa.Column('expires_at', sa.BigInteger(), nullable=False),
        sa.CheckConstraint('expires_at > created_at'))
    op.create_index('ix_person_quotes_payer_id', 'person_quotes', ['payer_id'])
    op.create_table('person_orders',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('quote_id', sa.String(36), sa.ForeignKey('person_quotes.id'), nullable=False),
        sa.Column('payer_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('beneficiary_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('request_id', sa.String(36), sa.ForeignKey('money_requests.id')),
        sa.Column('request_key', sa.String(120), nullable=False),
        sa.Column('status', sa.String(16), nullable=False),
        sa.Column('collection_status', sa.String(16), nullable=False),
        sa.Column('delivery_status', sa.String(16), nullable=False),
        sa.Column('created_at', sa.BigInteger(), nullable=False),
        sa.Column('expires_at', sa.BigInteger(), nullable=False),
        sa.UniqueConstraint('payer_id', 'request_key', name='uq_person_order_key'),
        sa.UniqueConstraint('quote_id', name='uq_person_order_quote'),
        sa.CheckConstraint("status IN ('READY','CANCELLED','EXPIRED')"),
        sa.CheckConstraint("collection_status = 'NOT_STARTED'"),
        sa.CheckConstraint("delivery_status = 'NOT_STARTED'"))
    op.create_index('ix_person_orders_payer_id', 'person_orders', ['payer_id'])
    op.create_index('uq_ready_order_request', 'person_orders', ['request_id'], unique=True,
        sqlite_where=sa.text("status = 'READY'"), postgresql_where=sa.text("status = 'READY'"))


def downgrade():
    for table in ('person_orders', 'person_quotes'):
        if op.get_bind().execute(sa.text('SELECT COUNT(*) FROM ' + table)).scalar():
            raise RuntimeError('Quote/order evidence exists; preserve it before downgrade.')
    op.drop_table('person_orders')
    op.drop_table('person_quotes')
