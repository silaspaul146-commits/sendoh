"""Mobile Money numbers people pay with and receive on, and number verification codes."""
from alembic import op
import sqlalchemy as sa

revision = 'a1d9c3ef0019'
down_revision = 'f6c1b9de0018'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('money_numbers',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('phone', sa.String(16), nullable=False),
        sa.Column('method', sa.String(8), nullable=False),
        sa.Column('verified_at', sa.BigInteger()),
        sa.Column('pay_default', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('receive_default', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('created_at', sa.BigInteger(), nullable=False),
        sa.Column('removed_at', sa.BigInteger()),
        sa.CheckConstraint("method IN ('MTN','ORANGE')", name='ck_money_number_method'))
    op.create_index('ix_money_numbers_user_id', 'money_numbers', ['user_id'])
    op.create_index('uq_money_number_active', 'money_numbers', ['user_id', 'phone'], unique=True,
                    sqlite_where=sa.text('removed_at IS NULL'), postgresql_where=sa.text('removed_at IS NULL'))
    op.create_table('number_challenges',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('purpose', sa.String(16), nullable=False),
        sa.Column('phone', sa.String(16), nullable=False),
        sa.Column('number_id', sa.String(36)),
        sa.Column('code_hash', sa.String(64), nullable=False),
        sa.Column('sent_at', sa.BigInteger(), nullable=False),
        sa.Column('expires_at', sa.BigInteger(), nullable=False),
        sa.Column('attempts', sa.Integer(), nullable=False),
        sa.CheckConstraint("purpose IN ('MONEY_NUMBER','SIGN_IN')", name='ck_number_challenge_purpose'))
    op.create_index('ix_number_challenges_user_id', 'number_challenges', ['user_id'])


def downgrade():
    op.drop_index('ix_number_challenges_user_id', 'number_challenges')
    op.drop_table('number_challenges')
    op.drop_index('uq_money_number_active', 'money_numbers')
    op.drop_index('ix_money_numbers_user_id', 'money_numbers')
    op.drop_table('money_numbers')
