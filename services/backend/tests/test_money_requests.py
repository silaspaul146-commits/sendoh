import hashlib,time
from sqlalchemy.orm import Session
from app.models import User, MoneyRequest
from test_collections import client, headers
from test_notifications import push_enabled_without_background_worker

def create(client, **patch):
    recipient=client.post('/api/v1/people/resolve',headers=headers(),json={'identity':'@bob'}).json()['id']
    return client.post('/api/v1/money-requests',headers=headers(key='request-key-1'),
        json={'recipient_id':recipient,'amount':3000,'reason':'Lunch',**patch})

def test_request_replay_inbox_and_decline(client):
    first=create(client);assert first.status_code==201,first.text
    r=first.json();assert create(client).json()['id']==r['id']
    assert create(client,amount=4000).status_code==409
    assert r['payment_available'] is False
    inbox=client.get('/api/v1/me/notifications',headers=headers('bob')).json()
    assert len(inbox['items'])==1 and inbox['items'][0]['request_id']==r['id']
    assert client.get('/api/v1/money-requests',headers=headers('bob')).json()['items'][0]['direction']=='RECEIVED'
    path='/api/v1/money-requests/'+r['id']+'/respond'
    assert client.post(path,headers=headers(),json={'action':'DECLINE'}).status_code==403
    for _ in range(2):
        assert client.post(path,headers=headers('bob'),json={'action':'DECLINE'}).json()['status']=='DECLINED'
    assert len(client.get('/api/v1/me/notifications',headers=headers()).json()['items'])==1
    assert client.post(path,headers=headers(),json={'action':'CANCEL'}).status_code==409

def test_private_identity_and_request_access(client):
    assert client.post('/api/v1/people/resolve',json={'identity':'bob'}).status_code==401
    assert client.post('/api/v1/people/resolve',headers=headers(),json={'identity':'alice'}).status_code==409
    assert client.post('/api/v1/people/resolve',headers=headers(),json={'identity':'@bob','from_qr':True}).status_code==409
    r=create(client).json()
    with Session(client.app.state.engine) as db:
        db.add(User(display_name='Eve',username='eve',token_hash=hashlib.sha256(b'eve').hexdigest()));db.commit()
    assert client.get('/api/v1/money-requests/'+r['id'],headers=headers('eve')).status_code==404
    assert client.get('/api/v1/money-requests',headers=headers('eve')).json()['items']==[]

def test_expiry_and_validation(client):
    assert create(client,expires_at=int(time.time())-1).status_code==422
    assert create(client,amount=True).status_code==422
    assert create(client,reason='   ').status_code==422
    r=create(client,expires_at=int(time.time())+600).json()
    with Session(client.app.state.engine) as db:
        db.get(MoneyRequest,r['id']).expires_at=int(time.time())-1;db.commit()
    assert client.get('/api/v1/money-requests/'+r['id'],headers=headers()).json()['status']=='EXPIRED'
    assert client.post('/api/v1/money-requests/'+r['id']+'/respond',headers=headers('bob'),json={'action':'DECLINE'}).status_code==409

def test_request_push_outbox(client):
    from test_notifications import register,dispatch,Sender
    register(client)
    assert create(client).status_code==201
    sender=Sender();dispatch(client,sender)
    assert len(sender.sent)==1
    assert sender.sent[0][1]==client.get('/api/v1/me/notifications',headers=headers('bob')).json()['items'][0]['id']

def test_cancel_suppresses_stale_received_push_and_is_idempotent(client):
    from test_notifications import register,dispatch,Sender
    register(client)
    r=create(client).json()
    path='/api/v1/money-requests/'+r['id']+'/respond'
    assert client.post(path,headers=headers('bob'),json={'action':'CANCEL'}).status_code==403
    for _ in range(2):
        assert client.post(path,headers=headers(),json={'action':'CANCEL'}).json()['status']=='CANCELLED'
    sender=Sender()
    for _ in range(3):dispatch(client,sender)
    # Only the cancellation remains eligible, not the original request alert.
    assert len(sender.sent)==1
    notifications=client.get('/api/v1/me/notifications',headers=headers('bob')).json()['items']
    assert len(notifications)==2
    delivered=next(n for n in notifications if n['id']==sender.sent[0][1])
    assert delivered['kind']=='REQUEST_CANCELLED'
