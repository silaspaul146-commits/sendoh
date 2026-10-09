"""Bind invitations to accounts or verified phones; preserve legacy name rows."""
from alembic import op
import sqlalchemy as sa

revision = 'c49f2d0e3003'
down_revision = 'b38e1c9d2002'
branch_labels = None
depends_on = None

def upgrade():
    # SQLite recreates the table and does not reflect unnamed checks.
    checks = (sa.CheckConstraint('expected_amount IS NULL OR expected_amount > 0'),) if op.get_bind().dialect.name == 'sqlite' else ()
    with op.batch_alter_table('participants', table_args=checks) as b:
        b.add_column(sa.Column('user_id', sa.String(36), nullable=True))
        b.add_column(sa.Column('invited_user_id', sa.String(36), nullable=True))
        b.add_column(sa.Column('invited_phone', sa.String(16), nullable=True))
        b.add_column(sa.Column('invitation_state', sa.String(16), nullable=False, server_default='UNVERIFIED'))
        b.add_column(sa.Column('invited_at', sa.BigInteger(), nullable=True))
        b.add_column(sa.Column('expires_at', sa.BigInteger(), nullable=True))
        b.create_foreign_key('fk_participant_user', 'users', ['user_id'], ['id'])
        b.create_foreign_key('fk_participant_invited_user', 'users', ['invited_user_id'], ['id'])
        b.create_unique_constraint('uq_participant_member', ['collection_id', 'user_id'])
        b.create_unique_constraint('uq_participant_invited_user', ['collection_id', 'invited_user_id'])
        b.create_unique_constraint('uq_participant_invited_phone', ['collection_id', 'invited_phone'])
        b.create_check_constraint('ck_participant_invitation_state', "invitation_state IN ('UNVERIFIED','PENDING','ACCEPTED','DECLINED','CANCELLED')")
        b.create_index('ix_participants_user_id', ['user_id'])
        b.create_index('ix_participants_invited_user_id', ['invited_user_id'])
        b.create_index('ix_participants_invited_phone', ['invited_phone'])
    op.create_table('invitation_rates',
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), primary_key=True),
        sa.Column('window_start', sa.BigInteger(), nullable=False),
        sa.Column('count', sa.Integer(), nullable=False))

def downgrade():
    op.drop_table('invitation_rates')
    checks = (sa.CheckConstraint('expected_amount IS NULL OR expected_amount > 0'),) if op.get_bind().dialect.name == 'sqlite' else ()
    with op.batch_alter_table('participants', table_args=checks) as b:
        for name in ('user_id', 'invited_user_id', 'invited_phone'):
            b.drop_index('ix_participants_' + name)
        for name in ('uq_participant_member', 'uq_participant_invited_user', 'uq_participant_invited_phone'):
            b.drop_constraint(name, type_='unique')
        b.drop_constraint('ck_participant_invitation_state', type_='check')
        b.drop_constraint('fk_participant_user', type_='foreignkey')
        b.drop_constraint('fk_participant_invited_user', type_='foreignkey')
        for name in ('user_id', 'invited_user_id', 'invited_phone', 'invitation_state', 'invited_at', 'expires_at'):
            b.drop_column(name)
