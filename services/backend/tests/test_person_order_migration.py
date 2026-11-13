from pathlib import Path
import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text


def test_quote_order_migration_preserves_accepted_terms(tmp_path, monkeypatch):
    url = f'sqlite:///{tmp_path}/orders.db'
    monkeypatch.setenv('DATABASE_URL', url)
    cfg = Config(str(Path(__file__).parents[1] / 'alembic.ini'))
    command.upgrade(cfg, 'd16a9e7fa010')
    command.upgrade(cfg, 'head')
    engine = create_engine(url)
    assert {'person_quotes','person_orders'} <= set(inspect(engine).get_table_names())
    command.downgrade(cfg, 'd16a9e7fa010')
    command.upgrade(cfg, 'head')
    with engine.begin() as db:
        db.execute(text("INSERT INTO users(id,display_name,token_hash,username) VALUES ('u','Alice','hash','alice')"))
        db.execute(text("INSERT INTO receiving_destinations(id,user_id,version,phone,method,created_at) VALUES ('d','u',1,'682248238','MTN',1)"))
        db.execute(text("INSERT INTO person_quotes(id,payer_id,beneficiary_id,destination_id,application_hash,policy_hash,policy,amounts,payer_phone,payer_method,created_at,expires_at) VALUES ('q','u','u','d','app','policy','{}','{}','600000001','MTN',1,2)"))
    with pytest.raises(RuntimeError, match='evidence exists'):
        command.downgrade(cfg, 'd16a9e7fa010')
    with engine.connect() as db:
        assert db.execute(text('SELECT id FROM person_quotes')).scalar() == 'q'
    engine.dispose()
