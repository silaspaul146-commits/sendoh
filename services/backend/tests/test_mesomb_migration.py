from pathlib import Path
import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text


def test_upgrade_preserves_records_and_refuses_evidence_loss(tmp_path, monkeypatch):
    url=f'sqlite:///{tmp_path}/migration.db'
    monkeypatch.setenv('DATABASE_URL',url)
    cfg=Config(str(Path(__file__).parents[1]/'alembic.ini'))
    command.upgrade(cfg,'f72c5a3b6006')
    engine=create_engine(url)
    with engine.begin() as db:
        db.execute(text("INSERT INTO users (id,display_name,username,token_hash) VALUES ('u','User','user','hash')"))
    command.upgrade(cfg,'head')
    with engine.connect() as db:
        assert db.execute(text('SELECT display_name FROM users')).scalar()=='User'
    assert 'provider_payments' in inspect(engine).get_table_names()
    assert any(i['name']=='uq_pending_provider_collection' and i['unique'] for i in inspect(engine).get_indexes('provider_payments'))
    command.downgrade(cfg,'f72c5a3b6006')
    command.upgrade(cfg,'head')
    with engine.begin() as db:
        db.execute(text("INSERT INTO mesomb_webhooks (event_id,body_hash,event_type,received_at) VALUES ('e','hash','payment.transaction.success',1)"))
    with pytest.raises(RuntimeError,match='evidence exists'):
        command.downgrade(cfg,'f72c5a3b6006')
    with engine.connect() as db:
        assert db.execute(text('SELECT COUNT(*) FROM mesomb_webhooks')).scalar()==1
    engine.dispose()
