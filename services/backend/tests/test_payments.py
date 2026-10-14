"""Staging ledger contract, attribution and replay checks."""
import pytest
from sqlalchemy import select, func
from sqlalchemy.orm import Session
from app.models import TestPayment as Payment, Activity, Notification
from app.payments import enabled
from dataclasses import replace
from test_collections import client, headers
from test_invitations import collection, bind_phone


def setup(client, monkeypatch, **patch):
    monkeypatch.setenv('SENDOH_TEST_PAYMENTS', '1')
    bind_phone(client)
    c = collection(client, **patch)
    token = c['share_url'].split('/')[-1]
    result = client.post('/api/v1/me/guest-collections/' + token + '/join', headers=headers('bob'), json={})
    assert result.status_code == 200
    return c, token


def create(client, c, key='payment-0001', amount=1000):
    return client.post('/api/v1/test-payments', headers=headers('bob', key),
        json={'collection_id': c['id'], 'amount': amount, 'method': 'MTN', 'note': 'Lunch'})


def test_saved_payment_receipt_totals_and_replay(client, monkeypatch):
    c, token = setup(client, monkeypatch, mode='EXPECTED_TOTAL', expected_amount=3000)
    first = create(client, c)
    assert first.status_code == 201, first.text
    p = first.json()
    assert p['status'] == 'PENDING' and p['payer_name'] == 'bob'
    assert create(client, c).json()['id'] == p['id']
    assert create(client, c, amount=999).status_code == 409
    endpoint = '/api/v1/test-payments/' + p['id'] + '/simulate'
    for _ in range(2):
        response = client.post(endpoint, headers=headers('bob'), json={'status': 'SUCCEEDED'})
        assert response.status_code == 200, response.text
    receipt = client.get('/api/v1/test-payments/' + p['id'], headers=headers('bob')).json()
    assert receipt['receipt_available'] and receipt['reference'].startswith('TEST-')
    assert receipt['fee_amount'] == 0 and receipt['total_amount'] == 1000
    summary = client.get('/api/v1/collections/' + c['id'], headers=headers()).json()
    assert summary['collected_amount'] == 0 and summary['test_collected_amount'] == 1000
    assert summary['participants'][0]['test_payment_status'] == 'Partial'
    assert summary['participants'][0]['test_paid_amount'] == 1000
    public = client.get('/api/v1/public/collections/' + token).json()
    assert public['test_collected_amount'] == 1000 and 'participants' not in public
    assert client.post(endpoint, headers=headers('bob'), json={'status':'FAILED'}).status_code == 409
    with Session(client.app.state.engine) as db:
        assert db.scalar(select(func.count()).select_from(Payment)) == 1
        assert db.scalar(select(func.count()).select_from(Notification).where(Notification.kind == 'TEST_PAYMENT')) == 2
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.message.like('TEST:%'))) == 1


@pytest.mark.parametrize('status', ['FAILED', 'CANCELLED'])
def test_failed_and_cancelled_do_not_count(client, monkeypatch, status):
    c, _ = setup(client, monkeypatch)
    p = create(client, c).json()
    r = client.post('/api/v1/test-payments/' + p['id'] + '/simulate', headers=headers('bob'), json={'status':status})
    assert r.status_code == 200 and not r.json()['receipt_available']
    summary = client.get('/api/v1/collections/' + c['id'], headers=headers()).json()
    assert summary['test_collected_amount'] == 0
    assert client.get('/api/v1/me/test-payments', headers=headers('bob')).json()['items'][0]['status'] == status


def test_owner_reads_but_cannot_simulate_someone_else(client, monkeypatch):
    c, _ = setup(client, monkeypatch)
    p = create(client, c).json()
    base = '/api/v1/test-payments/' + p['id']
    assert client.get(base, headers=headers()).status_code == 200
    assert client.post(base + '/simulate', headers=headers(), json={'status':'SUCCEEDED'}).status_code == 404
    assert client.get(base).status_code == 401
    assert client.get('/api/v1/collections/' + c['id'] + '/test-payments', headers=headers('bob')).status_code == 404
    assert client.get('/api/v1/me/test-payments', headers=headers()).json()['items'] == []


def test_flag_and_identity(client, monkeypatch):
    c = collection(client)
    monkeypatch.setenv('SENDOH_TEST_PAYMENTS', '0')
    assert create(client, c).status_code == 403
    monkeypatch.setenv('SENDOH_TEST_PAYMENTS', '1')
    assert not enabled(replace(client.app.state.settings, environment='production'))
    assert create(client, c).status_code == 403  # No verified phone or membership.
    bind_phone(client)
    assert create(client, c).status_code == 403  # Phone alone is not membership.
    assert client.post('/api/v1/test-payments', headers=headers('bob'), json={
        'collection_id':c['id'], 'amount':1000, 'method':'MTN', 'payer_id':'alice'}).status_code == 422


def test_guest_token_uses_same_ledger_and_minimum(client, monkeypatch):
    c, token = setup(client, monkeypatch, mode='MINIMUM_TOTAL', expected_amount=3000)
    assert create(client, c, amount=1000).status_code == 422
    response = client.post('/api/v1/test-payments', headers=headers('bob','guest-key-001'), json={
        'collection_token':token, 'amount':3000, 'method':'ORANGE'})
    assert response.status_code == 201, response.text
    p = response.json()
    rows = client.get('/api/v1/me/test-payments?collection_token=' + token, headers=headers('bob')).json()['items']
    assert rows[0]['id'] == p['id']
    assert client.get('/api/v1/collections/' + c['id'] + '/test-payments', headers=headers()).json()['items'][0]['id'] == p['id']
