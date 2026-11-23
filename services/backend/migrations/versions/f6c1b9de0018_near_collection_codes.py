"""Near2Pay codes can stand for a collection ("Contribute to ...") as well as a person."""
from alembic import op
import sqlalchemy as sa
revision = 'f6c1b9de0018'
down_revision = 'e4b8a6cd0017'
branch_labels = None
depends_on = None


def _checks():
    # SQLite rebuilds the table and does not reflect unnamed checks; restate them.
    if op.get_bind().dialect.name == 'sqlite':
        return (sa.CheckConstraint('amount IS NULL OR (amount > 0 AND amount <= 1000000000)'),)
    return ()


def upgrade():
    with op.batch_alter_table('near_codes', table_args=_checks()) as b:
        b.add_column(sa.Column('collection_id', sa.String(36), nullable=True))
        b.create_foreign_key('fk_near_code_collection', 'collections', ['collection_id'], ['id'])


def downgrade():
    # Codes expire within minutes; nothing durable is lost.
    with op.batch_alter_table('near_codes', table_args=_checks()) as b:
        b.drop_constraint('fk_near_code_collection', type_='foreignkey')
        b.drop_column('collection_id')
