from pathlib import Path
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text


def test_payment_migration_preserves_existing_records(tmp_path, monkeypatch):
    url = f'sqlite:///{tmp_path}/payment-migration.db'
    monkeypatch.setenv('DATABASE_URL', url)
    config = Config(str(Path(__file__).parents[1] / 'alembic.ini'))
    command.upgrade(config, 'd50a3e1f4004')
    engine = create_engine(url)
    try:
        with engine.begin() as db:
            db.execute(text("INSERT INTO users(id,display_name,token_hash) VALUES ('u','Existing member','hash')"))
        command.upgrade(config, 'head')
        assert 'test_payments' in inspect(engine).get_table_names()
        with engine.connect() as db:
            assert db.execute(text("SELECT display_name FROM users WHERE id='u'")).scalar_one() == 'Existing member'
            assert db.execute(text('SELECT COUNT(*) FROM test_payments')).scalar_one() == 0
        command.downgrade(config, 'd50a3e1f4004')
        assert 'test_payments' not in inspect(engine).get_table_names()
        command.upgrade(config, 'head')
        assert 'test_payments' in inspect(engine).get_table_names()
    finally:
        engine.dispose()
