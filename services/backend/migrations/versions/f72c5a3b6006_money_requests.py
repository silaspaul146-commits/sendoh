"""Money requests and non-collection notification destinations."""
from alembic import op
import sqlalchemy as sa
revision = 'f72c5a3b6006'
down_revision = 'e61b4f2a5005'
branch_labels = None
depends_on = None

def upgrade():
    op.create_table('money_requests',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('requester_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('recipient_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('amount', sa.BigInteger(), nullable=False),
        sa.Column('reason', sa.String(140), nullable=False),
        sa.Column('expires_at', sa.BigInteger()),
        sa.Column('status', sa.String(12), nullable=False),
        sa.Column('request_key', sa.String(120), nullable=False),
        sa.Column('fingerprint', sa.String(64), nullable=False),
        sa.Column('created_at', sa.BigInteger(), nullable=False),
        sa.UniqueConstraint('requester_id','request_key',name='uq_money_request_key'),
        sa.CheckConstraint('amount > 0 AND amount <= 1000000000'),
        sa.CheckConstraint('requester_id != recipient_id'),
        sa.CheckConstraint("status IN ('PENDING','DECLINED','CANCELLED')"))
    for field in ('requester_id','recipient_id'):
        op.create_index('ix_money_requests_'+field,'money_requests',[field])
    with op.batch_alter_table('notifications') as batch:
        batch.alter_column('collection_id', existing_type=sa.String(36), nullable=True)
        batch.alter_column('participant_id', existing_type=sa.String(36), nullable=True)
        batch.alter_column('invitation_version', existing_type=sa.Integer(), nullable=True)
        batch.add_column(sa.Column('request_id',sa.String(36),nullable=True))

def downgrade():
    if op.get_bind().execute(sa.text('SELECT COUNT(*) FROM money_requests')).scalar():
        raise RuntimeError('Money requests exist. Export and resolve rollback before downgrading.')
    with op.batch_alter_table('notifications') as batch:
        batch.drop_column('request_id')
        batch.alter_column('collection_id',existing_type=sa.String(36),nullable=False)
        batch.alter_column('participant_id',existing_type=sa.String(36),nullable=False)
        batch.alter_column('invitation_version',existing_type=sa.Integer(),nullable=False)
    op.drop_table('money_requests')
