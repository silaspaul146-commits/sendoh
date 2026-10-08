"""Add identity and rotating sessions without replacing existing users."""
from alembic import op
import sqlalchemy as sa

revision = 'b38e1c9d2002'
down_revision = 'a27d9b2e1001'
branch_labels = None
depends_on = None

def upgrade():
    with op.batch_alter_table('users') as batch:
        batch.add_column(sa.Column('username', sa.String(24), nullable=True))
        batch.add_column(sa.Column('avatar', sa.Text(), nullable=True))
        batch.create_unique_constraint('uq_users_username', ['username'])
    op.add_column('auth_sessions', sa.Column('family_id', sa.String(36), nullable=True))
    op.create_index('ix_auth_sessions_family_id', 'auth_sessions', ['family_id'])
    op.create_table('refresh_sessions',
        sa.Column('token_hash', sa.String(64), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('family_id', sa.String(36), nullable=False),
        sa.Column('expires_at', sa.BigInteger(), nullable=False),
        sa.Column('consumed', sa.Integer(), nullable=False))
    op.create_index('ix_refresh_sessions_user_id', 'refresh_sessions', ['user_id'])
    op.create_index('ix_refresh_sessions_family_id', 'refresh_sessions', ['family_id'])

def downgrade():
    op.drop_table('refresh_sessions')
    op.drop_index('ix_auth_sessions_family_id', table_name='auth_sessions')
    with op.batch_alter_table('auth_sessions') as batch:
        batch.drop_column('family_id')
    with op.batch_alter_table('users') as batch:
        batch.drop_constraint('uq_users_username', type_='unique')
        batch.drop_column('avatar')
        batch.drop_column('username')
