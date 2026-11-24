"""Family Trip closes: 48,000 confirmed Mobile Money, 6,000 cash, one payout, Round 2.

Marie (bob) pays 4,000 by Mobile Money + 1,000 cash. Eve pays 44,000 + 5,000 cash.
The fake provider reports a 2% collection fee per payment (80 + 880 = 960). The
synthetic Sendoh policy is 1% (480). Payout = 48,000 - 960 - 480 = 46,560.
These are sandbox fixtures, not provider-verified delivery.
"""
import json
import uuid

import pytest
from sqlalchemy import select, func

from app.models import Notification, Settlement
from app.settlement import run_due
from test_collections import headers
from test_invitations import bind_phone
from test_mesomb_lifecycle import client, due  # noqa: F401
from test_person_execution import Provider
from test_receiving import identify, save

POLICY = dict(version='settle-test-v1', sendoh_bps=100, sendoh_min=75, sendoh_cap=2000,
              payout_bps=0, payout_fixed=0)


@pytest.fixture
def trip(client, monkeypatch):
    client.app.state.mesomb_client = Provider()
    bind_phone(client)                               # Marie (bob)
    bind_phone(client, 'eve', '+237690222333')
    identify(client, 'alice', '+237682248238')       # Alain
    assert save(client).status_code == 200
    object.__setattr__(client.app.state.mesomb_config, 'test_phones',
                       frozenset(('670000000', '682248238')))
    monkeypatch.setenv('SENDOH_SANDBOX_SETTLEMENT_PAYOUTS', '1')
    monkeypatch.setenv('SENDOH_SANDBOX_SETTLEMENT_FEE_POLICY', json.dumps(POLICY))
    c = client.post('/api/v1/collections', headers=headers(key=str(uuid.uuid4())), json={
        'name': 'Family Trip', 'target_amount': 50000, 'mode': 'EXPECTED_TOTAL',
        'expected_amount': 5000, 'recurring': True}).json()
    token = c['share_url'].split('/')[-1]
    for who in ('bob', 'eve'):
        assert client.post(f'/api/v1/me/guest-collections/{token}/join', headers=headers(who),
                           json={}).status_code == 200
    return client, c


def pay(client, c, who, amount, settle=True):
    r = client.post('/api/v1/provider-payments', headers=headers(who, str(uuid.uuid4())), json=dict(
        collection_id=c['id'], amount=amount, method='MTN', payer_phone='670000000'))
    assert r.status_code == 201, r.text
    if settle:
        due(client, r.json()['id'])
    return r.json()['id']


def member(client, c, name):
    owned = client.get('/api/v1/collections/' + c['id'], headers=headers()).json()
    return next(p for p in owned['participants'] if p['username'] == name)


def record_cash(client, c):
    entries = [{'participant_id': member(client, c, 'bob')['id'], 'amount': 1000},
               {'participant_id': member(client, c, 'eve')['id'], 'amount': 5000}]
    for _ in range(2):  # a repeated tap records nothing twice
        r = client.post(f"/api/v1/collections/{c['id']}/cash", headers=headers(), json={'entries': entries})
        assert r.status_code == 200, r.text
    return r.json()


def overview(client, c):
    return client.get(f"/api/v1/collections/{c['id']}/settlement", headers=headers()).json()


def close(client, c, amount, key='close-trip-0001'):
    return client.post(f"/api/v1/collections/{c['id']}/settlement", headers=headers('alice', key),
                       json={'consent': 'CLOSE_AND_SEND', 'payout_amount': amount})


def deposits(client):
    return [d for kind, d in client.app.state.mesomb_client.calls if kind == 'deposit']


def sweep(client):
    with client.app.state.sessions() as db:
        db.execute(Settlement.__table__.update().values(next_check_at=0, lease_until=0))
        db.commit()
    run_due(client.app.state.sessions, client.app.state.mesomb_config, client.app.state.mesomb_client)


def ready_to_close(client, c):
    pay(client, c, 'bob', 4000)
    pay(client, c, 'eve', 44000)
    return record_cash(client, c)


def test_arithmetic_and_marie_gets_her_full_share(trip):
    client, c = trip
    o = ready_to_close(client, c)
    assert o['raised'] == dict(o['raised'], mobile_money=48000, cash=6000, total=54000, pending_count=0)
    q = o['quote']
    assert q['provider_fees'].startswith('960') and q['sendoh_fee'] == 480 and q['payout_cost'] == 0
    assert q['fees_total'] == 1440 and q['payout_amount'] == 46560 and q['cash'] == 6000
    assert o['destination'] == {'method': 'MTN', 'masked': '••• 238'}
    assert o['blockers'] == []
    # The orange bar's basis: confirmed Mobile Money plus recorded cash.
    totals = client.get('/api/v1/collections/' + c['id'], headers=headers()).json()['totals']
    assert totals['raised_amount'] == 54000 and totals['contributors'] == 2
    joined = client.get('/api/v1/me/joined-collections', headers=headers('bob')).json()[0]
    position = joined['contribution_summary']['position']
    assert position['state'] == 'FULFILLED'
    assert (position['confirmed_amount'], position['cash_amount'], position['paid_amount']) == (4000, 1000, 5000)
    assert joined['collection']['organizer_handle'] == '@alice'


def test_pending_contribution_is_named_and_holds_settlement(trip):
    client, c = trip
    ready_to_close(client, c)
    client.app.state.mesomb_client.empty = True
    pay(client, c, 'bob', 500, settle=False)
    o = overview(client, c)
    assert o['raised']['pending'] == [{'name': 'bob', 'amount': 500}]
    assert 'PAYMENTS_CONFIRMING' in [b['code'] for b in o['blockers']]
    assert close(client, c, 46560).status_code == 409
    assert deposits(client) == []


def test_close_once_uncertain_payout_and_repeated_delivery(trip):
    client, c = trip
    ready_to_close(client, c)
    client.app.state.mesomb_client.timeout = True  # the payout request times out
    first = close(client, c, 46560)
    assert first.status_code == 200, first.text
    assert first.json()['collection_status'] == 'CLOSED'
    assert first.json()['settlement']['state'] == 'SENDING'
    client.app.state.mesomb_client.timeout = False
    # Double tap and a different key: the same payout, never a second one.
    assert close(client, c, 46560).json()['settlement']['id'] == first.json()['settlement']['id']
    assert close(client, c, 46560, key='close-trip-0002').status_code == 409
    # Contributions stop once closed.
    r = client.post('/api/v1/provider-payments', headers=headers('bob', str(uuid.uuid4())), json=dict(
        collection_id=c['id'], amount=1000, method='MTN', payer_phone='670000000'))
    assert r.status_code == 404
    for _ in range(3):  # recovery and repeated confirmations
        sweep(client)
    o = overview(client, c)
    assert o['settlement']['state'] == 'DELIVERED' and o['collection_status'] == 'SETTLED'
    assert [d['amount'] for d in deposits(client)] == [46560]
    with client.app.state.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Notification)
                         .where(Notification.kind == 'SETTLEMENT_DELIVERED')) == 1
    # The payout does not move the group's progress.
    totals = client.get('/api/v1/collections/' + c['id'], headers=headers()).json()['totals']
    assert totals['raised_amount'] == 54000
    receipts = client.get('/api/v1/me/settlements', headers=headers()).json()['items']
    assert [(r['round'], r['state'], r['payout_amount']) for r in receipts] == [(1, 'DELIVERED', 46560)]


def test_round_two_starts_clean_and_round_one_stays_paid(trip):
    client, c = trip
    ready_to_close(client, c)
    close(client, c, 46560)
    sweep(client)
    r = client.post(f"/api/v1/collections/{c['id']}/rounds", headers=headers(),
                    json={'from_round': 1, 'expected_amount': 6000})
    assert r.status_code == 200, r.text
    o = r.json()
    assert o['round'] == 2 and o['raised']['total'] == 0 and o['settlement'] is None
    assert o['history'][0]['payout_amount'] == 46560 and o['history'][0]['state'] == 'DELIVERED'
    joined = client.get('/api/v1/me/joined-collections', headers=headers('bob')).json()[0]
    now = joined['contribution_summary']['position']
    assert now['state'] == 'NOT_STARTED' and now['expected_amount'] == 6000
    assert joined['collection']['round'] == 2
    # Round 1 stays paid, from the snapshot taken at close, despite the new rule.
    assert joined['previous_round'] == dict(round=1, state='FULFILLED', confirmed=4000, cash=1000,
                                            expected=5000, delivered=True)
