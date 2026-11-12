"""Recipient-owned receiving consent; no inferred mobile-money verification."""
from alembic import op
import sqlalchemy as sa

revision = 'd16a9e7fa010'
down_revision = 'c05f8d6e9009'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('receiving_destinations',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('version', sa.Integer(), nullable=False),
        sa.Column('phone', sa.String(16), nullable=False),
        sa.Column('method', sa.String(8), nullable=False),
        sa.Column('created_at', sa.BigInteger(), nullable=False),
        sa.UniqueConstraint('user_id', 'version', name='uq_receiving_destination_version'),
        sa.CheckConstraint('version > 0'),
        sa.CheckConstraint("method IN ('MTN','ORANGE')"))
    op.create_index('ix_receiving_destinations_user_id', 'receiving_destinations', ['user_id'])


def downgrade():
    if op.get_bind().execute(sa.text('SELECT COUNT(*) FROM receiving_destinations')).scalar():
        raise RuntimeError('Receiving consent exists; preserve it before downgrade.')
    op.drop_table('receiving_destinations')
