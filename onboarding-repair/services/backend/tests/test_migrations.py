import hashlib
from pathlib import Path
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text, inspect

def test_upgrade_preserves_legacy_organizer_and_collection(tmp_path, monkeypatch):
    url = f'sqlite:///{tmp_path}/upgrade.db'
    monkeypatch.setenv('DATABASE_URL', url)
    config = Config(str(Path(__file__).parents[1] / 'alembic.ini'))
    command.upgrade(config, '96cf77a9c739')
    engine = create_engine(url)
    with engine.begin() as db:
        db.execute(text('INSERT INTO users (id,display_name,token_hash) VALUES (:id,:name,:hash)'), {'id':'legacy','name':'Local organizer','hash':hashlib.sha256(b'legacy').hexdigest()})
        db.execute(text("INSERT INTO collections (id,organizer_id,public_token,name,description,currency,mode,status,created_at) VALUES ('birthday','legacy','old-link','Kboys Birthday','','XAF','ANY_AMOUNT','ACTIVE','2026-09-19')"))
    command.upgrade(config, 'head')
    with engine.connect() as db:
        assert db.execute(text("SELECT organizer_id,public_token FROM collections WHERE id='birthday'")).one() == ('legacy','old-link')
        assert db.execute(text("SELECT display_name FROM users WHERE id='legacy'")).scalar() == 'Local organizer'
    assert {'auth_sessions','phone_identities','otp_challenges'} <= set(inspect(engine).get_table_names())
    engine.dispose()
