"""A payment MeSomb never recorded stops holding the group after a day.

Seen on staging: one guest payment stayed "awaiting confirmation" for three days
while every MeSomb lookup returned no transaction. It held the collection's
pending total, blocked settlement and stopped the payer from paying again.
"""
from sqlalchemy import select

from app.models import Activity, ProviderPayment
from test_collections import headers
from test_mesomb_lifecycle import client, create, due, result, setup  # noqa: F401

DAY = 24 * 3600


def age(client, pid, seconds, attempts):
    with client.app.state.sessions() as db:
        p = db.get(ProviderPayment, pid)
        p.created_at -= seconds
        p.attempts = attempts
        db.commit()


def test_young_or_few_checks_stays_pending(client):
    c, _ = setup(client)
    client.app.state.mesomb_client.empty = True
    pid = create(client, c).json()['id']
    age(client, pid, DAY + 60, 2)          # old, but only a few checks
    due(client, pid)
    assert result(client, pid)['status'] == 'PENDING'
    age(client, pid, -(DAY + 60) + 3600, 10)  # many checks, but under a day old
    due(client, pid)
    assert result(client, pid)['status'] == 'PENDING'


def test_never_recorded_closes_as_failed_and_frees_the_payer(client):
    c, _ = setup(client)
    fake = client.app.state.mesomb_client
    fake.empty = True
    pid = create(client, c).json()['id']
    age(client, pid, DAY + 60, 6)
    due(client, pid)
    r = result(client, pid)
    assert (r['status'], r['phase'], r['review_reason']) == ('FAILED', 'FAILED', 'PROVIDER_NO_RECORD')
    assert r['reconciliation_required'] is False
    totals = client.get('/api/v1/collections/' + c['id'], headers=headers()).json()['totals']
    assert totals['pending_amount'] == 0 and totals['confirmed_amount'] == 0
    with client.app.state.sessions() as db:
        assert any('unsuccessful' in a.message for a in db.scalars(select(Activity)))
    # The payer can pay again; no new debit was ever made for the old one.
    calls = len(fake.calls)
    assert create(client, c, key='provider-key-002').status_code == 201
    assert len(fake.calls) == calls + 1


def test_late_provider_record_is_flagged_not_credited(client):
    c, _ = setup(client)
    fake = client.app.state.mesomb_client
    fake.empty = True
    pid = create(client, c).json()['id']
    age(client, pid, DAY + 60, 6)
    due(client, pid)
    fake.empty = False                      # MeSomb reports it after all
    due(client, pid)
    r = result(client, pid)
    assert r['status'] == 'FAILED' and r['review_reason'] == 'CONFLICTING_PROVIDER_OUTCOME'
    totals = client.get('/api/v1/collections/' + c['id'], headers=headers()).json()['totals']
    assert totals['confirmed_amount'] == 0
