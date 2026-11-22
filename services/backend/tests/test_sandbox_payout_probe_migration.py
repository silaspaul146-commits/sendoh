from pathlib import Path
import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text

def test_probe_migration_preserves_evidence(tmp_path,monkeypatch):
    url=f'sqlite:///{tmp_path}/probe.db'
    monkeypatch.setenv('DATABASE_URL',url)
    cfg=Config(str(Path(__file__).parents[1]/'alembic.ini'))
    command.upgrade(cfg,'b94e7c5d8008')
    command.upgrade(cfg,'head')
    engine=create_engine(url)
    assert 'sandbox_payout_probes' in inspect(engine).get_table_names()
    command.downgrade(cfg,'b94e7c5d8008')
    command.upgrade(cfg,'head')
    with engine.begin() as db:
        db.execute(text("INSERT INTO sandbox_payout_probes(application_hash,reference,created_at,updated_at,next_check_at,lease_until,submission_result,lookup_result) VALUES ('app','ref',1,1,0,0,'RESERVED_OUTCOME_UNKNOWN','NOT_CHECKED')"))
    with pytest.raises(RuntimeError,match='evidence exists'):
        command.downgrade(cfg,'b94e7c5d8008')
    with engine.connect() as db:
        assert db.execute(text('SELECT reference FROM sandbox_payout_probes')).scalar()=='ref'
    engine.dispose()
