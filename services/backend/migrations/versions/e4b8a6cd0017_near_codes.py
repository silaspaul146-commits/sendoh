"""Near2Pay short-lived identity codes and lookup throttling."""
from alembic import op
import sqlalchemy as sa
revision = 'e4b8a6cd0017'
down_revision = 'd2a7f5bc0016'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('near_codes',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('token_hash', sa.String(64), nullable=False, unique=True),
        sa.Column('short_hash', sa.String(64), nullable=False),
        sa.Column('amount', sa.BigInteger(), nullable=True),
        sa.Column('created_at', sa.BigInteger(), nullable=False),
        sa.Column('expires_at', sa.BigInteger(), nullable=False),
        sa.CheckConstraint('amount IS NULL OR (amount > 0 AND amount <= 1000000000)'))
    op.create_index('ix_near_codes_user_id', 'near_codes', ['user_id'])
    op.create_index('ix_near_codes_short_hash', 'near_codes', ['short_hash'])
    op.create_index('ix_near_codes_expires_at', 'near_codes', ['expires_at'])
    op.create_table('near_attempts',
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), primary_key=True),
        sa.Column('window_start', sa.BigInteger(), nullable=False),
        sa.Column('failures', sa.Integer(), nullable=False))


def downgrade():
    # Codes expire within minutes; nothing durable is lost.
    op.drop_table('near_attempts')
    op.drop_index('ix_near_codes_expires_at', 'near_codes')
    op.drop_index('ix_near_codes_short_hash', 'near_codes')
    op.drop_index('ix_near_codes_user_id', 'near_codes')
    op.drop_table('near_codes')
