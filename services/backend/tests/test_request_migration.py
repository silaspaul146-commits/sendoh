from pathlib import Path
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine,text

def test_request_migration_preserves_notification_and_delivery(tmp_path,monkeypatch):
    url=f'sqlite:///{tmp_path}/requests.db';monkeypatch.setenv('DATABASE_URL',url)
    config=Config(str(Path(__file__).parents[1]/'alembic.ini'));command.upgrade(config,'e61b4f2a5005')
    engine=create_engine(url)
    with engine.begin() as db:
        db.execute(text("INSERT INTO users (id,display_name,username,token_hash) VALUES ('u','User','user','hash')"))
        db.execute(text("INSERT INTO collections (id,organizer_id,public_token,name,description,currency,mode,status,created_at) VALUES ('c','u','public','Group','','XAF','ANY_AMOUNT','ACTIVE','2026-10-18')"))
        db.execute(text("INSERT INTO participants (id,collection_id,name,invitation_state,invitation_version) VALUES ('p','c','User','PENDING',1)"))
        db.execute(text("INSERT INTO notifications (id,user_id,collection_id,participant_id,invitation_version,kind,event_key,created_at) VALUES ('n','u','c','p',1,'INVITED','event',100)"))
    command.upgrade(config,'head')
    with engine.connect() as db:
        assert db.execute(text("SELECT collection_id,participant_id,request_id FROM notifications WHERE id='n'")).one()==('c','p',None)
    command.downgrade(config,'e61b4f2a5005')
    with engine.connect() as db:assert db.execute(text("SELECT id FROM notifications")).scalar()=='n'
    engine.dispose()
