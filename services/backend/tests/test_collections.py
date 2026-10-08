import hashlib, os
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from sqlalchemy import select, func
from app.main import create_app
from app.models import Base, User, Collection, Activity

@pytest.fixture
def client(tmp_path):
    application=create_app(os.getenv('TEST_DATABASE_URL',f'sqlite:///{tmp_path}/test.db'))
    Base.metadata.create_all(application.state.engine)
    with Session(application.state.engine) as db:
        db.add_all([User(display_name=n,token_hash=hashlib.sha256(n.encode()).hexdigest()) for n in ('alice','bob')]);db.commit()
    with TestClient(application) as c: yield c
    Base.metadata.drop_all(application.state.engine)

def headers(user='alice',key='create-0001'):
    return {'Authorization':f'Bearer {user}','Idempotency-Key':key}

def test_service_root_and_health(client):
    root=client.get('/')
    assert root.status_code==200
    assert root.json()['service']=='Sendoh API'
    assert client.get('/health').json()['status']=='ok'

def test_create_replay_and_private_public_views(client):
    body={'name':'Family support','participants':[{'name':'Private person'}]}
    first=client.post('/api/v1/collections',json=body,headers=headers())
    assert first.status_code==201
    data=first.json()
    assert client.post('/api/v1/collections',json=body,headers=headers()).json()==data
    assert len(client.get('/api/v1/collections',headers=headers()).json())==1
    public=client.get('/api/v1/public/collections/'+data['share_url'].split('/')[-1]).json()
    assert 'participants' not in public and 'id' not in public
    assert public['target_amount'] is None
    assert client.get('/api/v1/collections/'+data['id'],headers=headers('bob')).status_code==404
    assert client.get('/api/v1/collections/'+data['id']).status_code==401
    assert len(client.get('/api/v1/me/activity',headers=headers()).json())==1

def test_conflicting_key_is_rejected(client):
    client.post('/api/v1/collections',json={'name':'A'},headers=headers())
    r=client.post('/api/v1/collections',json={'name':'B'},headers=headers())
    assert r.status_code==409

@pytest.mark.parametrize('patch',[{'name':'  '},{'target_amount':0},{'target_amount':1.5},{'target_amount':True}, {'currency':'USD'},{'mode':'EXPECTED_TOTAL'}, {'expected_amount':200}, {'organizer_id':'spoof'}, {'deadline_at':'2026-10-01T10:00:00'}])
def test_invalid_payload_is_atomic(client,patch):
    result=client.post('/api/v1/collections',json={'name':'Valid',**patch},headers=headers())
    assert result.status_code==422
    assert client.get('/api/v1/collections',headers=headers()).json()==[]

def test_expectation_override_and_draft(client):
    r=client.post('/api/v1/collections',json={'name':'Dues','mode':'EXPECTED_TOTAL','expected_amount':3000,'publish':False,'participants':[{'name':'One'},{'name':'Two','expected_amount':5000}]},headers=headers())
    assert r.status_code==201
    d=r.json();assert d['share_url'] is None
    assert [p['expected_amount'] for p in d['participants']]==[3000,5000]

def test_same_key_different_actors(client):
    for name in ['alice','bob']:
        assert client.post('/api/v1/collections',json={'name':name},headers=headers(name)).status_code==201
    assert len(client.get('/api/v1/collections',headers=headers()).json())==1

def test_missing_key(client):
    assert client.post('/api/v1/collections',json={'name':'A'},headers={'Authorization':'Bearer alice'}).status_code==422

def test_concurrent_retries(client):
    if client.app.state.engine.dialect.name != 'postgresql':
        pytest.skip('Requires PostgreSQL locking semantics; exercised in CI')
    from concurrent.futures import ThreadPoolExecutor
    def submit(_): return client.post('/api/v1/collections',json={'name':'Concurrent'},headers=headers())
    with ThreadPoolExecutor(max_workers=4) as pool:
        responses=list(pool.map(submit,range(4)))
    assert all(r.status_code==201 for r in responses)
    assert len({r.json()['id'] for r in responses})==1
    assert len(client.get('/api/v1/me/activity',headers=headers()).json())==1
