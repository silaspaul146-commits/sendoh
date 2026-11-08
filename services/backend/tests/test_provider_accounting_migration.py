from pathlib import Path
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text
import pytest


def test_accounting_upgrade_preserves_old_amount_and_guards_downgrade(tmp_path, monkeypatch):
    url = f'sqlite:///{tmp_path}/accounting.db'
    monkeypatch.setenv('DATABASE_URL', url)
    cfg = Config(str(Path(__file__).parents[1] / 'alembic.ini'))
    command.upgrade(cfg, 'a83d6b4c7007')
    engine = create_engine(url)
    with engine.begin() as db:
        # SQLite FK checks off on this standalone historical fixture connection.
        db.execute(text("""INSERT INTO provider_payments
          (id,collection_id,participant_id,payer_id,beneficiary_id,request_key,fingerprint,
           application_hash,mode,amount,method,payer_phone,status,attempts,next_check_at,
           lease_until,created_at,updated_at)
          VALUES ('p','c','member','u','owner','key','hash','app','SANDBOX',1000,'MTN',
                  '600000001','SUCCEEDED',1,0,0,1,1)"""))
    command.upgrade(cfg, 'head')
    with engine.connect() as db:
        row = db.execute(text('SELECT amount,confirmed_provider_fee,accounting_verified_at FROM provider_payments')).one()
        assert tuple(row) == (1000, None, None)
    command.downgrade(cfg, 'a83d6b4c7007')
    command.upgrade(cfg, 'head')
    with engine.begin() as db:
        db.execute(text('UPDATE provider_payments SET confirmed_gross=1000,confirmed_provider_fee=20,confirmed_net=980,accounting_verified_at=2'))
    with pytest.raises(RuntimeError, match='Accounting evidence exists'):
        command.downgrade(cfg, 'a83d6b4c7007')
    with engine.connect() as db:
        assert db.execute(text('SELECT confirmed_net FROM provider_payments')).scalar() == 980
    engine.dispose()
