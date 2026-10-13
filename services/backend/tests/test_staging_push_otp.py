import hashlib
import time
from dataclasses import replace
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.auth import router
from app.config import load_settings
from app.models import Base, User, PhoneIdentity, PushDevice, RefreshSession


def test_push_otp_only_to_existing_live_bound_devices(tmp_path, monkeypatch):
    engine = create_engine(f'sqlite:///{tmp_path}/otp.db', connect_args={'check_same_thread':False})
    Base.metadata.create_all(engine)
    sessions = sessionmaker(engine)
    now = int(time.time())
    with sessions() as db:
        db.add(User(id='member',display_name='Member',token_hash='hash'))
        db.flush()
        db.add(PhoneIdentity(phone='+237690123456',user_id='member'))
        db.add(RefreshSession(token_hash='refresh',user_id='member',family_id='family',expires_at=now+1000,consumed=0))
        db.add(PushDevice(user_id='member',family_id='family',token='trusted-device',token_hash='devicehash',platform='android',active=1,updated_at=now,expires_at=now+1000))
        db.commit()
    sent=[]; fallback=[]
    class Sender:
        def send(self, token, challenge, *, otp): sent.append((token,otp))
    def database():
        with sessions() as db: yield db
    settings=replace(load_settings('sqlite://'),environment='staging',otp_provider='log')
    app=FastAPI()
    app.include_router(router(database, lambda:None, lambda:None, settings, Sender()))
    monkeypatch.setenv('SENDOH_STAGING_PUSH_OTP','1')
    monkeypatch.setattr('app.auth.deliver_otp',lambda *args: fallback.append(args) or 'staging-log')
    with TestClient(app) as client:
        assert client.post('/api/v1/auth/code',json={'phone':'+237690123456','token':'attacker-device'}).status_code==422
        response=client.post('/api/v1/auth/code',json={'phone':'+237690123456'})
        assert response.json()['delivery']=='staging-push'
        assert sent[0][0]=='trusted-device' and len(sent[0][1])==6
        assert not fallback
        assert client.post('/api/v1/auth/code',json={'phone':'+237690123457'}).json()['delivery']=='staging-log'
        assert len(sent)==1 and len(fallback)==1
