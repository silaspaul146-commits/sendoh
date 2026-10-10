import importlib
import time
from types import SimpleNamespace
import pytest
from sqlalchemy import select, func
from sqlalchemy.orm import Session, sessionmaker
from app.models import Notification, PushDevice, PushDelivery, Participant, RefreshSession
from app.push import process_one, SendFailure, FCMSender, lifespan_for
from test_collections import client, headers
from test_invitations import collection, invite, respond, cancel, bind_phone

@pytest.fixture(autouse=True)
def push_enabled_without_background_worker(monkeypatch):
    module = importlib.import_module('app.main')
    monkeypatch.setattr(module, 'configured_sender', lambda: object())
    monkeypatch.setattr(module, 'lifespan_for', lambda sessions, sender, env: lifespan_for(sessions, None, env))

def register(client, user='bob', token='test-device-token-1234567890'):
    return client.post('/api/v1/me/push-devices/register', headers=headers(user),
                       json={'token': token, 'platform':'android'})

def inbox(client, user='bob', **params):
    return client.get('/api/v1/me/notifications', headers=headers(user), params=params)

class Sender:
    def __init__(self, failure=None):
        self.sent, self.failure = [], failure
    def send(self, token, notification_id):
        self.sent.append((token, notification_id))
        if self.failure:
            raise self.failure

def dispatch(client, sender):
    return process_one(sessionmaker(client.app.state.engine, expire_on_commit=False), sender, 'development')

def test_invitation_notification_is_private_idempotent_and_readable(client):
    register(client)
    c = collection(client)
    p = invite(client, c, key='notif-repeat-1').json()
    invite(client, c, key='notif-repeat-1')
    response = inbox(client)
    data = response.json()
    assert response.headers['Cache-Control'] == 'no-store'
    assert data['unread_count'] == 1 and len(data['items']) == 1
    n = data['items'][0]
    assert n['kind'] == 'INVITED' and n['invitation_available'] is True
    assert 'token' not in response.text and 'phone' not in response.text
    assert inbox(client, 'alice').json()['items'] == []
    assert client.post('/api/v1/me/notifications/' + n['id'] + '/read', headers=headers(), json={}).status_code == 404
    assert inbox(client, 'alice', before=n['id']).status_code == 404
    for _ in range(2):
        assert client.post('/api/v1/me/notifications/' + n['id'] + '/read', headers=headers('bob'), json={}).status_code == 200
    assert inbox(client).json()['unread_count'] == 0
    sender = Sender()
    dispatch(client, sender)
    assert sender.sent == []  # Already read notifications are not pushed.
    assert respond(client, p).status_code == 200
    assert respond(client, p).status_code == 200
    assert [n['kind'] for n in inbox(client, 'alice').json()['items']] == ['ACCEPTED']

def test_phone_invites_materialize_once_after_verified_identity(client):
    c = collection(client)
    invite(client, c, {'phone':'+237690123456'})
    assert inbox(client).json()['items'] == []
    bind_phone(client)
    assert inbox(client).json()['unread_count'] == 1
    assert inbox(client).json()['unread_count'] == 1

def test_cancel_and_reinvite_create_distinct_generations(client):
    register(client)
    c = collection(client)
    p = invite(client, c).json()
    old = inbox(client).json()['items'][0]['id']
    cancel(client, c, p)
    invite(client, c)
    rows = inbox(client).json()['items']
    assert len(rows) == 3
    assert next(n for n in rows if n['id'] == old)['invitation_available'] is False
    sender = Sender()
    while dispatch(client, sender):
        pass
    assert old not in [n for _, n in sender.sent]

def test_retry_persists_and_unregistered_token_is_disabled(client):
    register(client)
    invite(client, collection(client))
    dispatch(client, Sender(SendFailure('PROVIDER_RETRY')))
    with Session(client.app.state.engine) as db:
        job = db.scalar(select(PushDelivery))
        assert job.state == 'PENDING' and job.attempts == 1 and job.due_at > int(time.time())
        job.due_at = 0
        db.commit()
    dispatch(client, Sender(SendFailure('UNREGISTERED', permanent=True, invalid_token=True)))
    with Session(client.app.state.engine) as db:
        assert db.scalar(select(PushDelivery)).state == 'DEAD'
        assert db.scalar(select(PushDevice)).active == 0
        assert db.scalar(select(func.count()).select_from(Notification)) == 1

def test_expired_lease_recovered_without_repeating_completed_job(client):
    register(client)
    invite(client, collection(client))
    with Session(client.app.state.engine) as db:
        job = db.scalar(select(PushDelivery))
        job.state, job.lease_until, job.lease_owner = 'SENDING', 0, 'abandoned-worker'
        db.commit()
    sender = Sender()
    assert dispatch(client, sender)
    assert not dispatch(client, sender)
    assert len(sender.sent) == 1

@pytest.mark.parametrize('action', ['logout', 'disable', 'expired', 'other-account', 'revoked-family'])
def test_no_delivery_after_device_or_session_changes(client, action):
    token = 'test-device-token-1234567890'
    register(client, token=token)
    invite(client, collection(client))
    if action == 'logout':
        client.post('/api/v1/auth/logout', headers=headers('bob'), json={})
    elif action == 'disable':
        client.post('/api/v1/me/push-devices/disable', headers=headers('bob'), json={})
    elif action == 'other-account':
        register(client, user='alice', token=token)
    else:
        with Session(client.app.state.engine) as db:
            device = db.scalar(select(PushDevice))
            if action == 'expired':
                device.expires_at = 0
            else:
                device.family_id = 'revoked-family'
                db.scalar(select(PushDelivery)).family_id = device.family_id
            db.commit()
    sender = Sender()
    dispatch(client, sender)
    assert sender.sent == []
    with Session(client.app.state.engine) as db:
        assert db.scalar(select(PushDelivery)).state == 'SKIPPED'

def test_device_registration_validation_limit_and_no_token_disclosure(client, monkeypatch):
    assert client.post('/api/v1/me/push-devices/register', json={'token':'x'*30,'platform':'android'}).status_code == 401
    assert register(client, token='bad').status_code == 422
    family = ['family-0']
    monkeypatch.setattr('app.notifications.family_for', lambda *args: (family[0], int(time.time()) + 3600))
    for i in range(5):
        family[0] = f'family-{i}'
        response = register(client, token=f'device-{i}-' + 'x'*25)
        assert response.status_code == 200 and 'token' not in response.text
    family[0] = 'sixth-family'
    assert register(client, token='another-'+'x'*25).status_code == 409
    family[0] = 'family-0'
    assert register(client, token='device-0-'+'x'*25).status_code == 200

def test_rotating_token_replaces_same_session_registration(client):
    register(client)
    invite(client, collection(client))
    for i in range(7):
        assert register(client, token=f'rotated-{i}-' + 'x'*25).status_code == 200
    with Session(client.app.state.engine) as db:
        assert db.scalar(select(func.count()).select_from(PushDevice).where(PushDevice.active == 1)) == 1
    sender = Sender()
    dispatch(client, sender)
    assert sender.sent == []
    assert inbox(client).json()['unread_count'] == 1

def test_notification_pagination_has_no_duplicates(client):
    c = collection(client)
    p = invite(client, c).json()
    with Session(client.app.state.engine) as db:
        first = db.scalar(select(Notification))
        for i in range(55):
            db.add(Notification(user_id=first.user_id, collection_id=c['id'], participant_id=p['id'],
                invitation_version=1, kind='INVITED', event_key=f'pagination-{i}', created_at=first.created_at))
        db.commit()
    first = inbox(client).json()
    second = inbox(client, before=first['next_cursor']).json()
    ids = [n['id'] for n in first['items'] + second['items']]
    assert len(ids) == len(set(ids)) == 56
    assert second['next_cursor'] is None

def test_fcm_payload_has_generic_text_and_retryable_errors(monkeypatch):
    sender = object.__new__(FCMSender)
    sender.credentials = SimpleNamespace(valid=True, token='oauth-secret')
    sender.url = 'https://fcm.googleapis.com/v1/projects/test/messages:send'
    captured = {}
    def post(url, **kwargs):
        captured.update(kwargs)
        return SimpleNamespace(status_code=200)
    monkeypatch.setattr('app.push.httpx.post', post)
    sender.send('device-private-token', 'notification-id')
    message = captured['json']['message']
    assert message['data'] == {'notification_id':'notification-id'}
    assert message['notification']['title'] == 'Sendoh'
    assert 'collection_id' not in str(message)
    assert captured['timeout'] == 15
    monkeypatch.setattr('app.push.httpx.post', lambda *a, **k: SimpleNamespace(
        status_code=429, json=lambda: {'error':{}}))
    with pytest.raises(SendFailure) as error:
        sender.send('token', 'id')
    assert error.value.code == 'PROVIDER_RETRY' and not error.value.permanent

def test_two_workers_do_not_send_the_same_claim(client):
    if client.app.state.engine.dialect.name != 'postgresql':
        pytest.skip('PostgreSQL concurrent queue claims run in CI')
    from concurrent.futures import ThreadPoolExecutor
    register(client)
    invite(client, collection(client))
    sender = Sender()
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(lambda _: dispatch(client, sender), range(2)))
    assert len(sender.sent) == 1
