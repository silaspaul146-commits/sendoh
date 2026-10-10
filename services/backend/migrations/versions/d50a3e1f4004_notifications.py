"""Durable user notifications and leased push outbox."""
from alembic import op
import sqlalchemy as sa

revision = 'd50a3e1f4004'
down_revision = 'c49f2d0e3003'
branch_labels = None
depends_on = None

def upgrade():
    op.add_column('participants', sa.Column('invitation_version', sa.Integer(), nullable=False, server_default='1'))
    op.create_table('notifications',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('collection_id', sa.String(36), sa.ForeignKey('collections.id'), nullable=False),
        sa.Column('participant_id', sa.String(36), sa.ForeignKey('participants.id'), nullable=False),
        sa.Column('invitation_version', sa.Integer(), nullable=False),
        sa.Column('kind', sa.String(32), nullable=False),
        sa.Column('event_key', sa.String(160), unique=True, nullable=False),
        sa.Column('created_at', sa.BigInteger(), nullable=False),
        sa.Column('read_at', sa.BigInteger(), nullable=True))
    op.create_index('ix_notifications_user_id', 'notifications', ['user_id'])
    op.create_table('push_devices',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('family_id', sa.String(80), nullable=False),
        sa.Column('token', sa.Text(), nullable=False),
        sa.Column('token_hash', sa.String(64), unique=True, nullable=False),
        sa.Column('platform', sa.String(8), nullable=False),
        sa.Column('active', sa.Integer(), nullable=False),
        sa.Column('updated_at', sa.BigInteger(), nullable=False),
        sa.Column('expires_at', sa.BigInteger(), nullable=False))
    op.create_index('ix_push_devices_user_id', 'push_devices', ['user_id'])
    op.create_index('ix_push_devices_family_id', 'push_devices', ['family_id'])
    op.create_table('push_deliveries',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('notification_id', sa.String(36), sa.ForeignKey('notifications.id'), nullable=False),
        sa.Column('device_id', sa.String(36), sa.ForeignKey('push_devices.id'), nullable=False),
        sa.Column('token_hash', sa.String(64), nullable=False),
        sa.Column('family_id', sa.String(80), nullable=False),
        sa.Column('state', sa.String(12), nullable=False),
        sa.Column('attempts', sa.Integer(), nullable=False),
        sa.Column('due_at', sa.BigInteger(), nullable=False),
        sa.Column('lease_until', sa.BigInteger(), nullable=False),
        sa.Column('lease_owner', sa.String(36), nullable=True),
        sa.Column('last_code', sa.String(40), nullable=True),
        sa.UniqueConstraint('notification_id', 'device_id', name='uq_notification_device'))
    op.create_index('ix_push_deliveries_due_at', 'push_deliveries', ['due_at'])

def downgrade():
    op.drop_table('push_deliveries')
    op.drop_table('push_devices')
    op.drop_table('notifications')
    op.drop_column('participants', 'invitation_version')
