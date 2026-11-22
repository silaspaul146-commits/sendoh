"""Guest and organizer agree on one contribution across a refused provider check."""
from sqlalchemy import select, func
from app.models import ProviderPaymentEvent
from app.mesomb_payments import unverified_reason
from app.providers.mesomb import ReconciliationRequired
from test_collections import headers
from test_mesomb_lifecycle import client, setup, create, due, result  # noqa: F401


def views(client, c):
    joined = client.get('/api/v1/me/joined-collections', headers=headers('bob')).json()[0]
    owned = client.get('/api/v1/collections/' + c['id'], headers=headers()).json()
    member = next(p for p in owned['participants'] if p['id'] == joined['id'])
    return joined['contribution_summary'], member, owned


def test_refused_lookup_then_verified_recovery(client):
    c, _ = setup(client)
    fake = client.app.state.mesomb_client
    original = fake.lookup

    def refused(external_id):
        raise ReconciliationRequired('HTTP_STATUS:403')

    pid = create(client, c).json()['id']
    fake.lookup = refused
    for _ in range(3):
        due(client, pid)
    payment = result(client, pid)
    assert payment['status'] == 'PENDING'
    assert payment['review_reason'] == 'PROVIDER_LOOKUP_HTTP_403'
    guest, member, owned = views(client, c)
    # Before confirmation both sides see 1,000 awaiting, nothing credited.
    assert guest['sandbox_pending_amount'] == member['sandbox_pending_amount'] == 1000
    assert guest['sandbox_paid_amount'] == member['sandbox_paid_amount'] == 0
    assert owned['sandbox_collected_amount'] == 0

    fake.lookup = original
    due(client, pid)
    due(client, pid)
    payment = result(client, pid)
    assert payment['status'] == 'SUCCEEDED' and payment['review_reason'] is None
    guest, member, owned = views(client, c)
    assert guest['sandbox_paid_amount'] == member['sandbox_paid_amount'] == 1000
    assert guest['sandbox_pending_amount'] == member['sandbox_pending_amount'] == 0
    assert owned['sandbox_collected_amount'] == 1000
    assert len(fake.calls) == 1  # one debit request, however many checks
    with client.app.state.sessions() as db:
        assert db.scalar(select(func.count()).select_from(ProviderPaymentEvent)) == 1


def test_confirmed_and_pending_money_stay_separate(client):
    c, _ = setup(client)
    first = create(client, c).json()['id']
    due(client, first)
    create(client, c, key='provider-key-002', amount=500)
    guest, member, _ = views(client, c)
    assert member['sandbox_paid_amount'] == 1000
    assert member['sandbox_pending_amount'] == 500
    assert member['sandbox_payment_pending'] is True
    assert guest['sandbox_paid_amount'] == 1000 and guest['sandbox_pending_amount'] == 500


def test_unverified_reason_is_allowlisted():
    assert unverified_reason('HTTP_STATUS:403') == 'PROVIDER_LOOKUP_HTTP_403'
    assert unverified_reason('TRANSPORT_OR_JSON_ERROR') == 'PROVIDER_UNREACHABLE'
    assert unverified_reason('LOOKUP_SHAPE_INVALID') == 'PROVIDER_RESPONSE_INVALID'
    assert unverified_reason('FIELD_MISMATCH:amount') == 'PROVIDER_UNVERIFIED'
    assert unverified_reason('HTTP_STATUS:403 secret=abc') == 'PROVIDER_UNVERIFIED'
