"""Link notifications to the provider payment they describe."""
from alembic import op
import sqlalchemy as sa
revision = 'a7d4c2e9b013'
down_revision = 'f38cb19fc012'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('notifications', sa.Column('payment_id', sa.String(36), nullable=True))


def downgrade():
    if op.get_bind().execute(sa.text('SELECT COUNT(*) FROM notifications WHERE payment_id IS NOT NULL')).scalar():
        raise RuntimeError('Contribution notifications exist; archive and review before downgrade.')
    op.drop_column('notifications', 'payment_id')
