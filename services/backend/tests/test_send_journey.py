"""Direct Send and Near2Pay: Marie (bob) sends Alain (alice) 2,500 FCFA, no request.

Both entry paths (handle, nearby code) resolve to the same recipient preview.
Identifying someone never creates an order. Delivery is the only "received".
"""
import json

import pytest
from sqlalchemy import select, func, update

from app.models import NearCode, Notification, PersonOrder, User
from test_collections import headers
from test_mesomb_lifecycle import client  # noqa: F401
from test_person_orders import prepared, POLICY  # noqa: F401
from test_person_execution import Provider, start, sweep


@pytest.fixture
def send(prepared, monkeypatch):
    c, _ = prepared
    monkeypatch.setenv('SENDOH_SANDBOX_PERSON_PAYMENTS', '1')
    monkeypatch.setenv('SENDOH_SANDBOX_PERSON_FEE_POLICY', json.dumps({**POLICY, 'payout_bps': 0}))
    object.__setattr__(c.app.state.mesomb_config, 'test_phones', frozenset(('682248238', '690000001')))
    c.app.state.mesomb_client = Provider()
    return c


def user_id(c, name):
    with c.app.state.sessions() as db:
        return db.scalar(select(User.id).where(User.username == name))


def orders(c):
    with c.app.state.sessions() as db:
        return db.scalar(select(func.count()).select_from(PersonOrder))


def activity(c, who):
    return c.get('/api/v1/person-payments/activity', headers=headers(who)).json()['items']


def test_handle_and_code_find_the_same_person_without_creating_anything(send):
    c = send
    by_handle = c.post('/api/v1/people/resolve', headers=headers('bob'), json={'identity': '@alice'}).json()
    code = c.post('/api/v1/near/codes', headers=headers('alice'), json={}).json()
    for value in (code['qr'], code['short_code']):
        by_code = c.post('/api/v1/near/resolve', headers=headers('bob'), json={'code': value}).json()
        assert by_code['person'] == by_handle
    assert by_handle['name'] == 'alice' and by_handle['identity'] == '@alice'
    assert by_handle['receiving_ready'] is True
    assert orders(c) == 0 and c.app.state.mesomb_client.calls == []
    # An expired code simply asks for a fresh one.
    with c.app.state.sessions() as db:
        db.execute(update(NearCode).values(expires_at=0))
        db.commit()
    expired = c.post('/api/v1/near/resolve', headers=headers('bob'), json={'code': code['short_code']})
    assert expired.status_code == 404 and 'new one' in expired.text


def test_missing_receiving_destination_is_known_before_any_charge(send):
    c = send
    eve = c.post('/api/v1/people/resolve', headers=headers('bob'), json={'identity': '@eve'}).json()
    assert eve['receiving_ready'] is False
    q = c.post('/api/v1/person-payments/quotes', headers=headers('bob'),
               json={'recipient_id': eve['id'], 'amount': 2500, 'payer_method': 'MTN'})
    assert q.status_code == 409
    for _ in range(2):
        r = c.post('/api/v1/people/receiving-reminder', headers=headers('bob'), json={'recipient_id': eve['id']})
        assert r.status_code == 200 and r.json()['receiving_ready'] is False
    items = c.get('/api/v1/me/notifications', headers=headers('eve')).json()['items']
    reminders = [n for n in items if n['kind'] == 'RECEIVING_SETUP_NEEDED']
    assert len(reminders) == 1  # once per payer, recipient and day
    assert reminders[0]['title'] == 'bob wants to pay you. Set where you receive money.'
    assert orders(c) == 0 and c.app.state.mesomb_client.calls == []


def test_direct_send_reaches_delivery_once_and_both_see_it_in_activity(send):
    c = send
    alice = user_id(c, 'alice')
    q = c.post('/api/v1/person-payments/quotes', headers=headers('bob'),
               json={'recipient_id': alice, 'amount': 2500, 'payer_method': 'MTN'})
    assert q.status_code in (200, 201), q.text
    q = q.json()
    assert q['recipient']['name'] == 'alice' and q['receiving_masked'] == '••• 238'
    assert q['reason'] is None and q['amounts']['recipient_amount'] == 2500
    o = c.post('/api/v1/person-payments/orders', headers=headers('bob', 'send-order-0001'),
               json={'quote_id': q['id'], 'consent': 'ACCEPT_QUOTED_TOTAL'}).json()
    # Prepared, not started: Alain sees nothing yet.
    assert activity(c, 'alice') == []
    # Approve, then a duplicate tap and an interrupted reopen.
    assert start(c, o).json()['phase'] == 'AWAITING_APPROVAL'
    assert start(c, o).json()['id'] == o['id']
    assert c.post('/api/v1/person-payments/orders', headers=headers('bob', 'send-order-0001'),
                  json={'quote_id': q['id'], 'consent': 'ACCEPT_QUOTED_TOTAL'}).json()['id'] == o['id']
    sweep(c)  # collected from Marie; delivery pending
    sent, = activity(c, 'bob')
    got, = activity(c, 'alice')
    assert sent['direction'] == 'SENT' and got['direction'] == 'RECEIVED'
    assert sent['phase'] == got['phase'] == 'DELIVERING'
    assert got['receipt_available'] is False
    with c.app.state.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Notification)
                         .where(Notification.kind == 'PERSON_RECEIVED')) == 0
    sweep(c)  # delivery verified
    sweep(c)  # duplicate check
    for who in ('alice', 'bob'):
        item, = activity(c, who)
        assert item['phase'] == 'DELIVERED' and item['receipt_available'] is True
    assert [k for k, _ in c.app.state.mesomb_client.calls] == ['collect', 'deposit']
    with c.app.state.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Notification)
                         .where(Notification.kind == 'PERSON_RECEIVED')) == 1
