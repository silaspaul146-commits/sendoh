import time

from sqlalchemy import select, func
from sqlalchemy.orm import Session

from app.models import User, PhoneIdentity, ReceivingDestination, MoneyRequest
from test_collections import client, headers
from test_money_requests import create


def identify(client, name='alice', phone='+237682248238'):
    with Session(client.app.state.engine) as db:
        user = db.scalar(select(User).where(User.username == name))
        db.add(PhoneIdentity(user_id=user.id, phone=phone))
        db.commit()
        return user.id


def save(client, name='alice', method='MTN', version=0, **extra):
    return client.post('/api/v1/me/receiving-destination', headers=headers(name), json=dict(
        method=method, expected_version=version,
        consent='RECEIVE_ON_MY_AUTHENTICATED_PHONE', **extra))


def test_recipient_consent_requires_identity_and_rejects_payer_selected_phone(client):
    assert save(client).status_code == 409
    identify(client)
    assert save(client, phone='600000001').status_code == 422
    assert save(client, user_id='bob').status_code == 422
    assert save(client, method='GUESS').status_code == 422
    assert client.get('/api/v1/me/receiving-destination').status_code == 401
    assert client.post('/api/v1/me/receiving-destination', headers=headers(),
        json={'method': 'MTN', 'expected_version': 0}).status_code == 422


def test_consent_replay_version_history_and_privacy(client):
    uid = identify(client)
    a = save(client)
    assert a.status_code == 200
    data = a.json()
    assert data['version'] == 1
    assert data['destination']['provider_verified'] is False
    assert '682248238' not in a.text
    assert save(client).json() == data
    assert save(client, method='ORANGE', version=0).status_code == 409
    assert save(client, method='ORANGE', version=1).json()['version'] == 2
    assert save(client, method='MTN', version=0).status_code == 409
    with Session(client.app.state.engine) as db:
        rows = db.scalars(select(ReceivingDestination).where(
            ReceivingDestination.user_id == uid).order_by(ReceivingDestination.version)).all()
        assert [r.method for r in rows] == ['MTN', 'ORANGE']
    assert client.get('/api/v1/me/receiving-destination', headers=headers('bob')).json() == {
        'version': 0, 'destination': None}


def test_identity_change_invalidates_old_destination(client):
    uid = identify(client)
    save(client)
    with Session(client.app.state.engine) as db:
        db.get(PhoneIdentity, '+237682248238').phone = '+237690000001'
        db.commit()
    own = client.get('/api/v1/me/receiving-destination', headers=headers()).json()
    assert own['destination']['identity_current'] is False
    assert save(client, version=1).json()['version'] == 2


def test_request_preflight_uses_requester_as_beneficiary_not_debtor(client):
    identify(client)
    identify(client, 'bob', '+237690000001')
    save(client)
    r = create(client).json()
    response = client.post('/api/v1/person-payments/preflight', headers=headers('bob'),
        json={'request_id': r['id']})
    assert response.status_code == 200
    p = response.json()
    assert p['recipient']['identity'] == '@alice'
    assert p['recipient_amount'] == 3000 and p['receiving_details_ready'] is True
    assert p['quote'] is None and p['can_pay'] is False
    assert p['blockers'] == ['FEE_QUOTE_NOT_CONFIGURED', 'RECIPIENT_DELIVERY_NOT_ENABLED']
    assert '682248238' not in response.text and '8238' not in response.text
    assert client.post('/api/v1/person-payments/preflight', headers=headers(),
        json={'request_id': r['id']}).status_code == 404
    assert client.post('/api/v1/person-payments/preflight', headers=headers('bob'),
        json={'request_id': r['id'], 'amount': 1}).status_code == 422
    with Session(client.app.state.engine) as db:
        assert db.get(MoneyRequest, r['id']).status == 'PENDING'


def test_cancelled_and_expired_requests_cannot_be_preflighted(client):
    r = create(client).json()
    with Session(client.app.state.engine) as db:
        db.get(MoneyRequest, r['id']).expires_at = int(time.time()) - 1
        db.commit()
    assert client.post('/api/v1/person-payments/preflight', headers=headers('bob'),
        json={'request_id': r['id']}).status_code == 409
    with Session(client.app.state.engine) as db:
        row = db.get(MoneyRequest, r['id'])
        row.expires_at = None
        row.status = 'CANCELLED'
        db.commit()
    assert client.post('/api/v1/person-payments/preflight', headers=headers('bob'),
        json={'request_id': r['id']}).status_code == 409


def test_direct_pay_preflight_reports_missing_details_without_inventing_quote(client):
    target = client.post('/api/v1/people/resolve', headers=headers(), json={'identity': 'bob'}).json()
    response = client.post('/api/v1/person-payments/preflight', headers=headers(),
        json={'recipient_id': target['id'], 'amount': 1000})
    data = response.json()
    assert data['purpose'] == 'PERSON_PAYMENT'
    assert data['recipient_amount'] == 1000
    assert data['receiving_details_ready'] is False
    assert 'PAYER_IDENTITY_REQUIRED' in data['blockers']
    assert 'RECIPIENT_RECEIVING_DETAILS_REQUIRED' in data['blockers']
    assert data['can_pay'] is False and data['quote'] is None
    for amount in (True, 1.5, 0, -1):
        assert client.post('/api/v1/person-payments/preflight', headers=headers(),
            json={'recipient_id': target['id'], 'amount': amount}).status_code == 422


def test_no_receiving_or_preflight_calls_dispatch_provider(client, monkeypatch):
    class Forbidden:
        def __getattr__(self, name):
            raise AssertionError('No money movement from preflight')
    client.app.state.mesomb_client = Forbidden()
    identify(client)
    save(client)
    r = create(client).json()
    for _ in range(3):
        assert client.post('/api/v1/person-payments/preflight', headers=headers('bob'),
            json={'request_id': r['id']}).status_code == 200
