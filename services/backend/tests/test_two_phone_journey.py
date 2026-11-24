"""Milestone: one contribution, two phones.

Alain (alice) organizes "Family trip" (60,000 goal, 5,000 share). Marie (bob)
joins from the link and contributes. Each step checks what BOTH people see:
Marie's own position, Alain's group totals, contributors, activity and Home.
"""
import time
import uuid

from sqlalchemy import select, func, update

from app.models import ProviderPayment, ProviderPaymentEvent, Notification
from app.mesomb_payments import reconcile
from app.providers.mesomb import ReconciliationRequired
from test_collections import headers
from test_invitations import bind_phone
from test_mesomb_lifecycle import client, due, result  # noqa: F401
from test_person_execution import Provider


def start(client):
    client.app.state.mesomb_client = Provider()
    bind_phone(client)
    r = client.post('/api/v1/collections', headers=headers(key=str(uuid.uuid4())), json={
        'name': 'Family trip', 'target_amount': 60000, 'mode': 'EXPECTED_TOTAL',
        'expected_amount': 5000})
    assert r.status_code == 201, r.text
    c = r.json()
    return c, c['share_url'].split('/')[-1]


def alain(client, c):
    return client.get('/api/v1/collections/' + c['id'], headers=headers()).json()


def marie(client):
    return client.get('/api/v1/me/joined-collections', headers=headers('bob')).json()[0]


def home(client):
    r = client.get('/api/v1/me/home', headers=headers())
    assert r.status_code == 200, r.text
    return r.json()


def pay(client, token, amount, key):
    return client.post('/api/v1/provider-payments', headers=headers('bob', key), json=dict(
        collection_token=token, amount=amount, method='MTN', payer_phone='670000000'))


def test_new_collection_and_joining_change_no_payment_figures(client):
    c, token = start(client)
    assert c['totals']['confirmed_amount'] == 0 and c['totals']['contributors'] == 0
    # Marie sees the purpose before giving any details (public view).
    public = client.get('/api/v1/public/collections/' + token).json()
    assert public['name'] == 'Family trip' and public['organizer_name'] == 'alice'
    assert public['expected_amount'] == 5000
    assert client.post(f'/api/v1/me/guest-collections/{token}/join', headers=headers('bob'),
                       json={}).status_code == 200
    a = alain(client, c)
    assert a['totals']['confirmed_amount'] == 0 and a['totals']['contributors'] == 0
    me = marie(client)['contribution_summary']['position']
    assert me['state'] == 'NOT_STARTED' and me['remaining_amount'] == 5000
    assert home(client)['collected_this_month']['amount'] == 0
    assert home(client)['recent'] == []


def test_review_uses_the_backend_quote(client):
    c, token = start(client)
    client.post(f'/api/v1/me/guest-collections/{token}/join', headers=headers('bob'), json={})
    q = client.post('/api/v1/provider-payments/quote', headers=headers('bob'), json=dict(
        collection_token=token, amount=5000, method='MTN', payer_phone='670000000'))
    assert q.status_code == 200, q.text
    q = q.json()
    assert q['credited_to'] == {'name': 'bob', 'collection': 'Family trip', 'organizer': 'alice'}
    assert q['contribution'] == 5000 and q['payer_fees'] == 0 and q['total'] == 5000
    assert q['payer_masked'] == '6•••••000' and q['method'] == 'MTN'
    assert q['fees_from'] == 'COLLECTION_PROCEEDS'


def test_contribution_counts_once_for_both_people(client):
    c, token = start(client)
    client.post(f'/api/v1/me/guest-collections/{token}/join', headers=headers('bob'), json={})
    created = pay(client, token, 5000, 'journey-key-0001')
    assert created.status_code == 201
    pid = created.json()['id']
    # Submitted, not confirmed: approval prompt, nothing counted, no reminder, no second charge.
    assert created.json()['status'] == 'PENDING' and created.json()['phase'] == 'AWAITING_APPROVAL'
    assert marie(client)['contribution_summary']['position']['state'] == 'CONFIRMING'
    a = alain(client, c)
    assert a['totals']['confirmed_amount'] == 0 and a['totals']['pending_amount'] == 5000
    assert client.get(f"/api/v1/collections/{c['id']}/reminders", headers=headers()).json()['eligible_count'] == 0
    assert pay(client, token, 5000, 'journey-key-0002').status_code == 409
    # Reopening recovers the same attempt.
    history = client.get(f'/api/v1/me/provider-payments?payer_only=true&collection_token={token}',
                         headers=headers('bob')).json()['items']
    assert [p['id'] for p in history] == [pid] and history[0]['status'] == 'PENDING'
    # Verified success, then repeated checks and a duplicate refresh.
    due(client, pid)
    due(client, pid)
    client.post(f'/api/v1/provider-payments/{pid}/refresh', headers=headers('bob'))
    p = result(client, pid)
    assert p['status'] == 'SUCCEEDED' and p['phase'] == 'CONFIRMED' and p['receipt_available']
    me = marie(client)['contribution_summary']['position']
    assert me['state'] == 'FULFILLED' and me['confirmed_amount'] == 5000 and me['remaining_amount'] == 0
    a = alain(client, c)
    assert a['totals']['confirmed_amount'] == 5000 and a['totals']['contributors'] == 1
    assert a['totals']['target_amount'] == 60000
    h = home(client)
    assert h['collected_this_month'] == dict(h['collected_this_month'], amount=5000, collections=1)
    assert [(r['name'], r['amount'], r['collection_name']) for r in h['recent']] == [('bob', 5000, 'Family trip')]
    with client.app.state.sessions() as db:
        assert db.scalar(select(func.count()).select_from(ProviderPaymentEvent)
                         .where(ProviderPaymentEvent.status == 'SUCCEEDED')) == 1
        assert db.scalar(select(func.count()).select_from(Notification)
                         .where(Notification.kind == 'CONTRIBUTION_CONFIRMED')) == 1


def test_partial_contribution_shows_what_is_left(client):
    c, token = start(client)
    client.post(f'/api/v1/me/guest-collections/{token}/join', headers=headers('bob'), json={})
    pid = pay(client, token, 2000, 'journey-partial-1').json()['id']
    due(client, pid)
    me = marie(client)['contribution_summary']['position']
    assert me['state'] == 'PARTIAL' and me['remaining_amount'] == 3000
    # Outstanding share only: a reminder is allowed for the 3,000 left.
    assert client.get(f"/api/v1/collections/{c['id']}/reminders", headers=headers()).json()['eligible_count'] == 1


def test_failure_and_unknown_outcomes(client):
    c, token = start(client)
    client.post(f'/api/v1/me/guest-collections/{token}/join', headers=headers('bob'), json={})
    fake = client.app.state.mesomb_client
    # A lookup error is not a failure: still pending, still no second charge.
    pid = pay(client, token, 5000, 'journey-unknown-1').json()['id']
    original = fake.lookup
    fake.lookup = lambda ref: (_ for _ in ()).throw(ReconciliationRequired('HTTP_STATUS:403'))
    due(client, pid)
    assert result(client, pid)['status'] == 'PENDING' and result(client, pid)['phase'] == 'CONFIRMING'
    assert pay(client, token, 5000, 'journey-unknown-2').status_code == 409
    # A definite failure leaves totals unchanged and permits a new attempt.
    fake.lookup = original
    fake.rows[pid]['status'] = 'FAILED'
    due(client, pid)
    assert result(client, pid)['status'] == 'FAILED' and result(client, pid)['phase'] == 'FAILED'
    assert alain(client, c)['totals']['confirmed_amount'] == 0
    assert marie(client)['contribution_summary']['position']['state'] == 'NOT_STARTED'
    assert pay(client, token, 5000, 'journey-retry-1').status_code == 201
