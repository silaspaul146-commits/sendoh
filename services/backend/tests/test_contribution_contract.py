"""One payment-state contract, and confirmation notifications only after MeSomb confirms."""
from sqlalchemy import select, func
from app.models import Notification, Activity, ProviderPayment
from app.notifications import serialize
from test_collections import headers
from test_mesomb_lifecycle import client, setup, create, due  # noqa: F401


def member(client, c):
    owned = client.get('/api/v1/collections/' + c['id'], headers=headers()).json()
    joined = client.get('/api/v1/me/joined-collections', headers=headers('bob')).json()[0]
    row = next(p for p in owned['participants'] if p['id'] == joined['id'])
    return row['position'], joined['contribution_summary']['position'], owned['totals']


def test_position_moves_through_confirming_to_contributed(client):
    c, _ = setup(client)
    org, guest, totals = member(client, c)
    assert org == guest
    assert org['state'] == 'NOT_STARTED' and org['membership'] == 'ACCEPTED'
    assert totals['confirmed_amount'] == 0 and totals['cash_amount'] == 0

    pid = create(client, c).json()['id']
    org, guest, totals = member(client, c)
    assert org == guest
    assert org['state'] == 'CONFIRMING'
    assert org['pending_amount'] == 1000 and org['confirmed_amount'] == 0
    assert totals['pending_amount'] == 1000 and totals['confirmed_amount'] == 0

    due(client, pid)
    org, guest, totals = member(client, c)
    assert org == guest
    assert org['state'] in ('CONTRIBUTED', 'FULFILLED', 'PARTIAL')
    assert org['confirmed_amount'] == 1000 and org['pending_amount'] == 0
    assert totals['confirmed_amount'] == 1000 and totals['environment'] == 'SANDBOX'


def test_invited_member_has_no_payment_state(client):
    c, _ = setup(client)
    owned = client.get('/api/v1/collections/' + c['id'], headers=headers()).json()
    for p in owned['participants']:
        if p['invitation_state'] != 'ACCEPTED':
            assert p['position']['state'] in ('INVITED', 'NOT_JOINED', 'DECLINED', 'CANCELLED', 'EXPIRED')


def notes(client, user):
    return client.get('/api/v1/me/notifications', headers=headers(user)).json()


def contribution_notes(client, user):
    data = notes(client, user)
    items = data['items'] if isinstance(data, dict) else data
    return [n for n in items if n['kind'].startswith('CONTRIBUTION_') and n['kind'] != 'CONTRIBUTION_REMINDER']


def test_confirmation_notifies_organizer_and_payer_once(client):
    c, _ = setup(client)
    pid = create(client, c).json()['id']
    due(client, pid)  # stays PENDING? no: fake provider confirms on first lookup
    with client.app.state.sessions() as db:
        assert db.get(ProviderPayment, pid).status == 'SUCCEEDED'
    due(client, pid)
    due(client, pid)
    organizer = contribution_notes(client, 'alice')
    payer = contribution_notes(client, 'bob')
    assert len(organizer) == 1 and len(payer) == 1
    assert organizer[0]['title'] == f"bob contributed 1,000 FCFA to {c['name']}"
    assert payer[0]['title'] == f"Your 1,000 FCFA contribution to {c['name']} is confirmed"
    assert organizer[0]['payment_id'] == pid and organizer[0]['environment'] == 'SANDBOX'
    with client.app.state.sessions() as db:
        messages = list(db.scalars(select(Activity.message).where(Activity.collection_id == c['id'])))
    assert f"bob contributed 1,000 FCFA to {c['name']} · Sandbox" in messages
    assert not any('no real money' in m for m in messages)


def test_no_contribution_notification_before_confirmation(client):
    c, _ = setup(client)
    fake = client.app.state.mesomb_client
    fake.status = 'PENDING'
    pid = create(client, c).json()['id']
    due(client, pid)
    assert contribution_notes(client, 'alice') == [] and contribution_notes(client, 'bob') == []
    fake.status = 'FAILED'
    due(client, pid)
    assert contribution_notes(client, 'alice') == [] and contribution_notes(client, 'bob') == []
    with client.app.state.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Notification)
                         .where(Notification.payment_id == pid)) == 0


def test_organizer_history_is_filtered_by_collection_with_names(client):
    c, _ = setup(client)
    pid = create(client, c).json()['id']
    rows = client.get('/api/v1/me/provider-payments?collection_id=' + c['id'],
                      headers=headers()).json()['items']
    assert [r['id'] for r in rows] == [pid]
    assert rows[0]['payer_name'] == 'bob'
    assert client.get('/api/v1/me/provider-payments?collection_id=' + c['id'],
                      headers=headers('eve')).json()['items'] == []
