from pathlib import Path
import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text


def test_receiving_migration_and_retained_consent(tmp_path, monkeypatch):
    url = f'sqlite:///{tmp_path}/receiving.db'
    monkeypatch.setenv('DATABASE_URL', url)
    cfg = Config(str(Path(__file__).parents[1] / 'alembic.ini'))
    command.upgrade(cfg, 'c05f8d6e9009')
    command.upgrade(cfg, 'head')
    engine = create_engine(url)
    assert 'receiving_destinations' in inspect(engine).get_table_names()
    command.downgrade(cfg, 'c05f8d6e9009')
    command.upgrade(cfg, 'head')
    with engine.begin() as db:
        db.execute(text("INSERT INTO users(id,display_name,token_hash,username) VALUES ('u','Alice','hash','alice')"))
        db.execute(text("INSERT INTO receiving_destinations(id,user_id,version,phone,method,created_at) VALUES ('d','u',1,'682248238','MTN',1)"))
    with pytest.raises(RuntimeError, match='Receiving consent exists'):
        command.downgrade(cfg, 'c05f8d6e9009')
    with engine.connect() as db:
        assert db.execute(text('SELECT version FROM receiving_destinations')).scalar() == 1
    engine.dispose()
