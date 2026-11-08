"""Preserve verified collect gross, fees and net without inventing old values."""
from alembic import op
import sqlalchemy as sa
revision = 'b94e7c5d8008'
down_revision = 'a83d6b4c7007'
branch_labels = None
depends_on = None


def upgrade():
    for name in ('confirmed_gross', 'confirmed_provider_fee', 'confirmed_net'):
        op.add_column('provider_payments', sa.Column(name, sa.Numeric(20, 6), nullable=True))
    op.add_column('provider_payments', sa.Column('accounting_verified_at', sa.BigInteger(), nullable=True))
    # Existing successful attempts retain unknown fees until provider lookup.
    # Do not infer a tariff or fabricate a zero fee.


def downgrade():
    if op.get_bind().execute(sa.text('SELECT COUNT(*) FROM provider_payments WHERE accounting_verified_at IS NOT NULL')).scalar():
        raise RuntimeError('Accounting evidence exists; archive and review before downgrade.')
    for name in ('accounting_verified_at', 'confirmed_net', 'confirmed_provider_fee', 'confirmed_gross'):
        op.drop_column('provider_payments', name)
