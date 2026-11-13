from pathlib import Path
import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text


def test_execution_migration_empty_roundtrip_and_data_guard(tmp_path, monkeypatch):
    url=f'sqlite:///{tmp_path}/execution.db'
    monkeypatch.setenv('DATABASE_URL',url)
    cfg=Config(str(Path(__file__).parents[1]/'alembic.ini'))
    command.upgrade(cfg,'e27ba08fb011')
    command.upgrade(cfg,'head')
    engine=create_engine(url)
    assert {'person_executions','person_payment_legs','provider_reference_claims'} <= set(inspect(engine).get_table_names())
    command.downgrade(cfg,'e27ba08fb011')
    command.upgrade(cfg,'head')
    # This SQLite migration-only connection has FK checks disabled, allowing a
    # minimal evidence sentinel to exercise the explicit destructive-drop guard.
    with engine.begin() as db:
        db.execute(text("INSERT INTO person_executions(order_id,application_hash,state,created_at,updated_at) VALUES ('sentinel','app','COLLECTING',1,1)"))
    with pytest.raises(RuntimeError,match='Execution evidence exists'):
        command.downgrade(cfg,'e27ba08fb011')
    engine.dispose()
