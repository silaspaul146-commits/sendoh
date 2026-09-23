"""Add development phone verification without changing existing organizer data."""
from alembic import op
import sqlalchemy as sa
revision = 'a27d9b2e1001'
down_revision = '96cf77a9c739'
branch_labels = None
depends_on = None

def upgrade():
    op.create_table('phone_identities', sa.Column('phone', sa.String(16), primary_key=True),
                    sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False, unique=True))
    op.create_table('otp_challenges', sa.Column('phone', sa.String(16), primary_key=True),
                    sa.Column('challenge_id', sa.String(36), nullable=False, unique=True),
                    sa.Column('code_hash', sa.String(64), nullable=False),
                    sa.Column('sent_at', sa.BigInteger(), nullable=False),
                    sa.Column('expires_at', sa.BigInteger(), nullable=False),
                    sa.Column('attempts', sa.Integer(), nullable=False))
    op.create_table('auth_sessions', sa.Column('token_hash', sa.String(64), primary_key=True),
                    sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
                    sa.Column('expires_at', sa.BigInteger(), nullable=False))
    op.create_index('ix_auth_sessions_user_id', 'auth_sessions', ['user_id'])

def downgrade():
    op.drop_table('auth_sessions')
    op.drop_table('otp_challenges')
    op.drop_table('phone_identities')
