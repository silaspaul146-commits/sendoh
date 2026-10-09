from pathlib import Path
import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError


def test_upgrade_keeps_manual_people_and_amount_check(tmp_path, monkeypatch):
    url = f'sqlite:///{tmp_path}/invitations.db'
    monkeypatch.setenv('DATABASE_URL', url)
    config = Config(str(Path(__file__).parents[1] / 'alembic.ini'))
    command.upgrade(config, 'b38e1c9d2002')
    engine = create_engine(url)
    with engine.begin() as db:
        db.execute(text("INSERT INTO users(id,display_name,token_hash) VALUES ('u','Alice','hash')"))
        db.execute(text("INSERT INTO collections(id,organizer_id,public_token,name,description,currency,mode,status,created_at) VALUES ('c','u','link','Family','','XAF','ANY_AMOUNT','ACTIVE','2026-10-01')"))
        db.execute(text("INSERT INTO participants(id,collection_id,name,expected_amount) VALUES ('p','c','Legacy person',5000)"))
    command.upgrade(config, 'head')
    with engine.connect() as db:
        assert db.execute(text("SELECT name,expected_amount,invitation_state,user_id FROM participants WHERE id='p'")).one() == ('Legacy person',5000,'UNVERIFIED',None)
    with pytest.raises(IntegrityError), engine.begin() as db:
        db.execute(text("UPDATE participants SET expected_amount=-1 WHERE id='p'"))
    command.downgrade(config, 'b38e1c9d2002')
    with pytest.raises(IntegrityError), engine.begin() as db:
        db.execute(text("UPDATE participants SET expected_amount=-1 WHERE id='p'"))
    command.upgrade(config, 'head')
    engine.dispose()
