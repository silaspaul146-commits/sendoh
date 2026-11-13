import json
import time

import pytest
from sqlalchemy import select, func
from sqlalchemy.orm import Session

from app.fee_quotes import FeePolicy, calculate, ceiling_div
from app.models import User, PersonQuote, PersonOrder, MoneyRequest
from test_mesomb_lifecycle import client
from test_collections import headers
from test_receiving import identify, save
from test_money_requests import create

# Synthetic arithmetic fixture; NOT a published MeSomb or Sendoh tariff.
POLICY = dict(version='test-v1', collect_bps=200, collect_fixed=0,
    payout_bps=100, payout_fixed=0, sendoh_bps=0, sendoh_min=75, sendoh_cap=2000)


@pytest.fixture
def prepared(client, monkeypatch):
    monkeypatch.setenv('SENDOH_SANDBOX_PERSON_FEE_POLICY', json.dumps(POLICY))
    identify(client)
    identify(client, 'bob', '+237690000001')
    assert save(client).status_code == 200
    r = create(client).json()
    return client, r


def quote(client, request_id):
    return client.post('/api/v1/person-payments/quotes', headers=headers('bob'),
        json={'request_id': request_id, 'payer_method': 'MTN'})


def accept(client, q, key='accept-order-0001', who='bob'):
    return client.post('/api/v1/person-payments/orders', headers=headers(who, key),
        json={'quote_id': q['id'], 'consent': 'ACCEPT_QUOTED_TOTAL'})


def test_integer_fee_math_preserves_principal_and_minimal_total():
    for bps in (0, 1, 200, 300, 9999):
        policy = FeePolicy(**{**POLICY, 'collect_bps': bps})
        for principal in (1, 99, 1000, 10001):
            a = calculate(principal, policy)
            assert a['recipient_amount'] == principal
            assert a['total_debit'] == principal + a['total_fees']
            assert a['expected_collection_net'] == principal + a['sendoh_fee'] + a['delivery_fee']
            less = a['total_debit'] - 1
            assert less - ceiling_div(less * bps, 10000) < a['expected_collection_net']
    with pytest.raises(ValueError):
        calculate(1_000_000_000, FeePolicy(**POLICY))


def test_fee_minimum_cap_fixed_fees_and_invalid_policy():
    p = FeePolicy(**{**POLICY, 'collect_fixed': 10, 'payout_fixed': 20, 'sendoh_bps': 500})
    assert calculate(1, p)['sendoh_fee'] == 75
    assert calculate(100000, p)['sendoh_fee'] == 2000
    a = calculate(3000, p)
    assert a['total_debit'] - a['collection_fee'] == 3000 + a['delivery_fee'] + a['sendoh_fee']
    for change in ({'collect_bps': True}, {'sendoh_cap': 1}, {'payout_bps': -1}, {'collect_bps': 10000}):
        with pytest.raises(ValueError):
            FeePolicy(**{**POLICY, **change})


def test_quote_and_order_recovery_never_claims_payment(prepared):
    c, r = prepared
    response = quote(c, r['id'])
    assert response.status_code == 201, response.text
    q = response.json()
    assert q['recipient']['identity'] == '@alice'
    assert q['amounts']['recipient_amount'] == 3000
    assert q['expires_at'] - q['created_at'] == 300
    assert '682248238' not in response.text
    o = accept(c, q)
    assert o.status_code == 201, o.text
    data = o.json()
    assert data['collection_status'] == data['delivery_status'] == 'NOT_STARTED'
    assert data['receipt_available'] is False and data['execution_available'] is False
    assert accept(c, q).json()['id'] == data['id']
    assert accept(c, q, 'another-order-key').status_code == 409
    assert c.get('/api/v1/person-payments/orders', headers=headers('bob')).json()['items'][0]['id'] == data['id']
    with Session(c.app.state.engine) as db:
        assert db.get(MoneyRequest, r['id']).status == 'PENDING'
        assert db.scalar(select(func.count()).select_from(PersonOrder)) == 1
    assert c.app.state.mesomb_client.calls == []


def test_no_quote_without_explicit_policy(prepared, monkeypatch):
    c, r = prepared
    for policy in ('', '{invalid}', '{}'):
        monkeypatch.setenv('SENDOH_SANDBOX_PERSON_FEE_POLICY', policy)
        assert quote(c, r['id']).status_code == 503


@pytest.mark.parametrize('change', ['expiry', 'policy', 'destination', 'phone', 'request'])
def test_accept_rechecks_all_terms(prepared, monkeypatch, change):
    c, r = prepared
    q = quote(c, r['id']).json()
    if change == 'policy':
        monkeypatch.setenv('SENDOH_SANDBOX_PERSON_FEE_POLICY', json.dumps({**POLICY, 'collect_bps': 300}))
    elif change == 'destination':
        assert save(c, method='ORANGE', version=1).status_code == 200
    else:
        from app.models import PhoneIdentity
        with Session(c.app.state.engine) as db:
            if change == 'expiry':
                row = db.get(PersonQuote, q['id'])
                row.created_at = int(time.time()) - 600
                row.expires_at = int(time.time()) - 1
            elif change == 'phone':
                db.get(PhoneIdentity, '+237690000001').phone = '+237690000002'
            else:
                db.get(MoneyRequest, r['id']).status = 'CANCELLED'
            db.commit()
    assert accept(c, q).status_code == 409
    with Session(c.app.state.engine) as db:
        assert db.scalar(select(func.count()).select_from(PersonOrder)) == 0


def test_one_ready_order_per_request_and_cancelled_order_releases_it(prepared):
    c, r = prepared
    q1, q2 = quote(c, r['id']).json(), quote(c, r['id']).json()
    o = accept(c, q1).json()
    assert accept(c, q2, 'another-order-key').status_code == 409
    for _ in range(2):
        assert c.post('/api/v1/person-payments/orders/'+o['id']+'/cancel',
            headers=headers('bob')).json()['status'] == 'CANCELLED'
    assert accept(c, q2, 'another-order-key').status_code == 201
    assert accept(c, q2).status_code == 409  # Original key still binds original quote.


def test_cancel_request_invalidates_prepared_order_atomically(prepared):
    c, r = prepared
    o = accept(c, quote(c, r['id']).json()).json()
    response = c.post('/api/v1/money-requests/'+r['id']+'/respond', headers=headers(), json={'action':'CANCEL'})
    assert response.status_code == 200
    assert c.get('/api/v1/person-payments/orders/'+o['id'], headers=headers('bob')).json()['status'] == 'CANCELLED'
    assert quote(c, r['id']).status_code == 409


def test_quote_order_access_and_tampering(prepared):
    c, r = prepared
    q = quote(c, r['id']).json()
    assert accept(c, q, who='alice').status_code == 404
    for who in ('alice','eve'):
        assert c.get('/api/v1/person-payments/quotes/'+q['id'], headers=headers(who)).status_code == 404
    assert c.post('/api/v1/person-payments/orders', headers=headers('bob'), json={
        'quote_id': q['id'], 'consent':'ACCEPT_QUOTED_TOTAL', 'amount':1}).status_code == 422
    o = accept(c, q).json()
    assert c.get('/api/v1/person-payments/orders/'+o['id'], headers=headers('alice')).status_code == 404
    assert c.post('/api/v1/person-payments/orders/'+o['id']+'/cancel', headers=headers('alice')).status_code == 404


def test_existing_order_replays_after_policy_changes(prepared, monkeypatch):
    c, r = prepared
    q = quote(c, r['id']).json()
    o = accept(c, q).json()
    monkeypatch.delenv('SENDOH_SANDBOX_PERSON_FEE_POLICY')
    assert accept(c, q).json()['id'] == o['id']


def test_direct_pay_uses_same_quote_engine(prepared):
    c, _ = prepared
    target = c.post('/api/v1/people/resolve', headers=headers('bob'), json={'identity':'alice'}).json()
    response = c.post('/api/v1/person-payments/quotes', headers=headers('bob'), json={
        'recipient_id':target['id'], 'amount':1500, 'payer_method':'ORANGE'})
    assert response.status_code == 201
    assert response.json()['purpose'] == 'PERSON_PAYMENT'
    assert accept(c, response.json()).status_code == 201


def test_request_expiry_bounds_quote(prepared):
    c, r = prepared
    with Session(c.app.state.engine) as db:
        db.get(MoneyRequest, r['id']).expires_at = int(time.time()) + 30
        db.commit()
    q = quote(c, r['id']).json()
    assert q['expires_at'] - q['created_at'] <= 30


def test_expired_prepared_order_does_not_block_new_quote(prepared):
    c, r = prepared
    q = quote(c, r['id']).json()
    o = accept(c, q).json()
    with Session(c.app.state.engine) as db:
        db.get(PersonOrder, o['id']).expires_at = int(time.time()) - 1
        db.commit()
    assert c.get('/api/v1/person-payments/orders/'+o['id'], headers=headers('bob')).json()['status'] == 'EXPIRED'
    newer = quote(c, r['id']).json()
    assert accept(c, newer, 'new-order-after-expiry').status_code == 201
    assert accept(c, q).json()['id'] == o['id']


def test_decline_request_invalidates_order(prepared):
    c, r = prepared
    o = accept(c, quote(c, r['id']).json()).json()
    response = c.post('/api/v1/money-requests/'+r['id']+'/respond', headers=headers('bob'), json={'action':'DECLINE'})
    assert response.status_code == 200
    assert c.get('/api/v1/person-payments/orders/'+o['id'], headers=headers('bob')).json()['status'] == 'CANCELLED'
