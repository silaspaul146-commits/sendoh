"""Durable one-shot sandbox payout probe; isolated from customer accounting."""
from alembic import op
import sqlalchemy as sa
revision = 'c05f8d6e9009'
down_revision = 'b94e7c5d8008'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('sandbox_payout_probes',
        sa.Column('application_hash', sa.String(64), primary_key=True),
        sa.Column('reference', sa.String(36), nullable=False, unique=True),
        sa.Column('created_at', sa.BigInteger(), nullable=False),
        sa.Column('updated_at', sa.BigInteger(), nullable=False),
        sa.Column('next_check_at', sa.BigInteger(), nullable=False),
        sa.Column('lease_owner', sa.String(36), nullable=True),
        sa.Column('lease_until', sa.BigInteger(), nullable=False),
        sa.Column('submission_result', sa.String(48), nullable=False),
        sa.Column('lookup_result', sa.String(48), nullable=False),
        sa.Column('evidence', sa.JSON(), nullable=True))


def downgrade():
    if op.get_bind().execute(sa.text('SELECT COUNT(*) FROM sandbox_payout_probes')).scalar():
        raise RuntimeError('Payout probe evidence exists; review before downgrade.')
    op.drop_table('sandbox_payout_probes')
