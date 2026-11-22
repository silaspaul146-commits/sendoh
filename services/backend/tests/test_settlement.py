"""Close and send: what was raised, what reaches the organizer, and never sending twice."""
import json
import pytest
from sqlalchemy import select, func

from app.models import Settlement, Collection, Notification
from app.notifications import serialize
from app.settlement import run_due, reconcile
from test_collections import headers
from test_mesomb_lifecycle import client, setup, create, due  # noqa: F401
from test_person_execution import Provider
from test_receiving import identify, save

# Synthetic engineering policy for arithmetic only; NOT an approved Sendoh price.
POLICY = dict(version='settle-test-v1', sendoh_bps=100, sendoh_min=75, sendoh_cap=2000,
              payout_bps=0, payout_fixed=0)


@pytest.fixture
def ready(client, monkeypatch):
    client.app.state.mesomb_client = Provider()
    c, _ = setup(client)
    identify(client, 'alice', '+237682248238')
    assert save(client).status_code == 200
    object.__setattr__(client.app.state.mesomb_config, 'test_phones',
                       frozenset(('670000000', '682248238')))
    monkeypatch.setenv('SENDOH_SANDBOX_SETTLEMENT_PAYOUTS', '1')
    monkeypatch.setenv('SENDOH_SANDBOX_SETTLEMENT_FEE_POLICY', json.dumps(POLICY))
    pid = create(client, c).json()['id']
    due(client, pid)
    return client, c


def overview(client, c):
    return client.get(f"/api/v1/collections/{c['id']}/settlement", headers=headers()).json()


def close(client, c, amount, key='settle-key-0001'):
    return client.post(f"/api/v1/collections/{c['id']}/settlement", headers=headers('alice', key),
                       json={'consent': 'CLOSE_AND_SEND', 'payout_amount': amount})


def deposits(client):
    return [d for kind, d in client.app.state.mesomb_client.calls if kind == 'deposit']


def sweep(client):
    with client.app.state.sessions() as db:
        db.execute(Settlement.__table__.update().values(next_check_at=0))
        db.commit()
    run_due(client.app.state.sessions, client.app.state.mesomb_config, client.app.state.mesomb_client)


def test_quote_answers_raised_and_what_reaches_the_phone(ready):
    client, c = ready
    o = overview(client, c)
    assert o['blockers'] == []
    assert o['raised']['mobile_money'] == 1000 and o['raised']['cash'] == 0
    q = o['quote']
    # 1,000 confirmed; MeSomb reported 20 in fees; Sendoh minimum 75; nothing invented.
    assert q['provider_fees'] == '20' or q['provider_fees'].startswith('20')
    assert q['sendoh_fee'] == 75 and q['payout_cost'] == 0
    assert q['payout_amount'] == 905 and q['fees_total'] == 95
    assert o['destination'] == {'method': 'MTN', 'masked': '••• 238'}


def test_disabled_or_unpriced_settlement_is_unavailable_not_free(ready, monkeypatch):
    client, c = ready
    monkeypatch.delenv('SENDOH_SANDBOX_SETTLEMENT_FEE_POLICY')
    o = overview(client, c)
    assert o['quote'] is None
    assert 'SETTLEMENT_NOT_AVAILABLE' in [b['code'] for b in o['blockers']]
    assert close(client, c, 905).status_code == 409
    assert deposits(client) == []


def test_cash_is_raised_and_counts_for_the_member_but_is_never_sent(ready):
    client, c = ready
    member = next(p for p in client.get('/api/v1/collections/' + c['id'], headers=headers()).json()['participants']
                  if p['user_id'])
    r = client.post(f"/api/v1/collections/{c['id']}/cash", headers=headers(),
                   json={'entries': [{'participant_id': member['id'], 'amount': 500}]})
    assert r.status_code == 200, r.text
    o = r.json()
    assert o['raised'] == dict(o['raised'], mobile_money=1000, cash=500, total=1500)
    assert o['quote']['payout_amount'] == 905  # cash stays with the organizer, no fee on it
    joined = client.get('/api/v1/me/joined-collections', headers=headers('bob')).json()[0]
    position = joined['contribution_summary']['position']
    assert position['confirmed_amount'] == 1000 and position['cash_amount'] == 500
    assert position['paid_amount'] == 1500
    titles = [serialize_title(client, n) for n in notes(client, 'bob', 'CASH_RECORDED')]
    assert titles == [f"alice recorded 500 FCFA cash from you for {c['name']}"]
    # A member flags a mistake; the organizer hears once.
    for _ in range(2):
        assert client.post(f"/api/v1/collections/{c['id']}/cash/flag", headers=headers('bob')).status_code == 200
    assert len(notes(client, 'alice', 'CASH_FLAGGED')) == 1


def notes(client, user, kind):
    with client.app.state.sessions() as db:
        from app.models import User
        uid = db.scalar(select(User.id).where(User.username == user))
        return [n.id for n in db.scalars(select(Notification).where(
            Notification.user_id == uid, Notification.kind == kind))]


def serialize_title(client, nid):
    with client.app.state.sessions() as db:
        return serialize(db, db.get(Notification, nid))['title']


def test_close_and_send_reserves_then_sends_once_and_delivers_after_evidence(ready):
    client, c = ready
    first = close(client, c, 905)
    assert first.status_code == 200, first.text
    s = first.json()['settlement']
    assert s['state'] == 'SENDING' and s['delivered'] is False
    assert first.json()['collection_status'] == 'CLOSED'
    assert len(deposits(client)) == 1
    assert deposits(client)[0]['amount'] == 905 and deposits(client)[0]['receiver'] == '682248238'
    # Same key replays; another key cannot send a second payout.
    assert close(client, c, 905).json()['settlement']['id'] == s['id']
    assert close(client, c, 905, key='settle-key-0002').status_code == 409
    # Contributions stop once closed.
    assert create(client, c, key='provider-key-late').status_code == 404
    sweep(client)
    sweep(client)
    o = overview(client, c)
    assert o['settlement']['state'] == 'DELIVERED' and o['collection_status'] == 'SETTLED'
    assert len(deposits(client)) == 1
    delivered = notes(client, 'alice', 'SETTLEMENT_DELIVERED')
    settled = notes(client, 'bob', 'COLLECTION_SETTLED')
    assert len(delivered) == 1 and len(settled) == 1
    assert serialize_title(client, delivered[0]) == f"905 FCFA from {c['name']} delivered to your MTN MoMo"
    assert serialize_title(client, settled[0]) == f"{c['name']} is settled. Settlement delivered to alice."


def test_uncertain_submission_is_looked_up_never_resent(ready):
    client, c = ready
    client.app.state.mesomb_client.timeout = True
    r = close(client, c, 905)
    assert r.status_code == 200
    assert r.json()['settlement']['state'] == 'SENDING'
    client.app.state.mesomb_client.timeout = False
    for _ in range(3):
        sweep(client)
    assert len(deposits(client)) == 1
    assert overview(client, c)['settlement']['state'] == 'DELIVERED'


def test_failed_payout_needs_attention_and_is_never_resent(ready):
    client, c = ready
    client.app.state.mesomb_client.delivery_failed = True
    close(client, c, 905)
    sweep(client)
    sweep(client)
    o = overview(client, c)
    assert o['settlement']['state'] == 'REVIEW'
    assert o['settlement']['review_reason'] == 'PAYOUT_FAILED_FUNDS_RETAINED'
    assert o['collection_status'] == 'CLOSED'
    assert len(deposits(client)) == 1
    assert len(notes(client, 'alice', 'SETTLEMENT_REVIEW')) == 1
    assert notes(client, 'bob', 'COLLECTION_SETTLED') == []


def test_pending_payment_or_changed_amount_blocks_close(ready):
    client, c = ready
    assert close(client, c, 999).status_code == 409  # amounts changed since review
    client.app.state.mesomb_client.empty = True
    create(client, c, key='provider-key-pending', amount=500)
    o = overview(client, c)
    assert 'PAYMENTS_CONFIRMING' in [b['code'] for b in o['blockers']]
    assert close(client, c, 905).status_code == 409
    assert deposits(client) == []
    with client.app.state.sessions() as db:
        assert db.scalar(select(Collection.status).where(Collection.id == c['id'])) == 'ACTIVE'


def test_only_the_organizer_can_settle(ready):
    client, c = ready
    assert client.get(f"/api/v1/collections/{c['id']}/settlement", headers=headers('bob')).status_code == 404
    assert client.post(f"/api/v1/collections/{c['id']}/settlement", headers=headers('bob', 'settle-bob-0001'),
                       json={'consent': 'CLOSE_AND_SEND', 'payout_amount': 905}).status_code == 404


def test_contributors_can_still_see_a_closed_collection_but_not_pay(ready):
    client, c = ready
    token = c['share_url'].split('/')[-1]
    close(client, c, 905)
    public = client.get('/api/v1/public/collections/' + token)
    assert public.status_code == 200 and public.json()['status'] == 'CLOSED'
    context = client.get('/api/v1/me/guest-collections/' + token, headers=headers('bob')).json()
    assert context['participant']['contribution_summary']['position']['confirmed_amount'] == 1000
    assert create(client, c, key='provider-key-after-close').status_code == 404
