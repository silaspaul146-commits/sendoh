"""Request and Pay, two phones.

Alain (alice) asks Marie (bob) for money with a reason. Marie reviews and pays.
Collected from Marie is not delivered to Alain: neither person may be told
Alain received the money until delivery is verified.
"""
from sqlalchemy import select, func

from app.models import Notification
from test_collections import headers
from test_mesomb_lifecycle import client  # noqa: F401
from test_person_orders import prepared, quote, accept  # noqa: F401
from test_person_execution import flow, start, sweep  # noqa: F401


def req(c, r, who):
    return c.get('/api/v1/money-requests/' + r['id'], headers=headers(who)).json()


def order(c, o, who):
    response = c.get('/api/v1/person-payments/orders/' + o['id'], headers=headers(who))
    assert response.status_code == 200, response.text
    return response.json()


def kinds(c, who):
    items = c.get('/api/v1/me/notifications', headers=headers(who)).json()['items']
    return [n['kind'] for n in items]


def test_marie_sees_who_how_much_why_and_where_it_goes(prepared):
    c, r = prepared
    seen = req(c, r, 'bob')
    assert seen['direction'] == 'RECEIVED' and seen['status'] == 'PENDING'
    assert seen['requester']['name'] == 'alice' and seen['amount'] == 3000 and seen['reason'] == 'Lunch'
    assert seen['payment_phase'] is None
    q = quote(c, r['id']).json()
    # Alain's own configured destination, masked; actual fees and total from the server.
    assert q['recipient']['name'] == 'alice' and q['receiving_masked'] == '••• 238'
    assert q['receiving_method'] == 'MTN' and q['reason'] == 'Lunch'
    assert q['amounts']['recipient_amount'] == 3000
    assert q['amounts']['total_debit'] > 3000
    assert q['payer_masked'].endswith('001')


def test_collected_is_not_delivered_and_reopening_never_charges_twice(flow):
    c, r, o = flow
    first = start(c, o)
    assert first.status_code == 200, first.text
    assert first.json()['phase'] == 'AWAITING_APPROVAL'
    # Interrupted: reopening and approving again resumes the same payment.
    assert start(c, o).json()['id'] == o['id']
    assert len(c.app.state.mesomb_client.calls) == 1
    assert quote(c, r['id']).status_code in (409, 422)  # no second payment for this request
    for who in ('alice', 'bob'):
        assert req(c, r, who)['status'] == 'PROCESSING'
    # Collected from Marie, delivery to Alain still pending.
    sweep(c)
    for who in ('alice', 'bob'):
        seen = order(c, o, who)
        assert seen['phase'] == 'DELIVERING' and seen['receipt_available'] is False
        assert req(c, r, who)['payment_phase'] == 'DELIVERING'
        assert req(c, r, who)['status'] == 'PROCESSING'
    assert 'PERSON_RECEIVED' not in kinds(c, 'alice')
    assert start(c, o).json()['id'] == o['id']
    assert [k for k, _ in c.app.state.mesomb_client.calls] == ['collect', 'deposit']
    # Verified delivery: both see the request resolved, both can reopen the receipt.
    sweep(c)
    for who in ('alice', 'bob'):
        seen = order(c, o, who)
        assert seen['phase'] == 'DELIVERED' and seen['receipt_available'] is True
        assert req(c, r, who)['status'] == 'PAID'
        assert req(c, r, who)['payment_phase'] == 'DELIVERED'
    assert kinds(c, 'alice').count('PERSON_RECEIVED') == 1
    assert kinds(c, 'bob').count('PERSON_DELIVERED') == 1
    sweep(c)
    assert len(c.app.state.mesomb_client.calls) == 2


def test_delivery_failure_holds_funds_and_never_charges_again(flow):
    c, r, o = flow
    c.app.state.mesomb_client.delivery_failed = True
    start(c, o)
    sweep(c)
    sweep(c)
    for who in ('alice', 'bob'):
        assert order(c, o, who)['phase'] == 'REVIEW_FUNDS_HELD'
        assert req(c, r, who)['status'] == 'PAYMENT_REVIEW'
    assert 'PERSON_RECEIVED' not in kinds(c, 'alice')
    assert start(c, o).json()['id'] == o['id']
    assert [k for k, _ in c.app.state.mesomb_client.calls].count('collect') == 1


def test_declined_request_tells_alain_and_cannot_be_paid(prepared):
    c, r = prepared
    declined = c.post(f"/api/v1/money-requests/{r['id']}/respond", headers=headers('bob'),
                      json={'action': 'DECLINE'})
    assert declined.status_code == 200 and declined.json()['status'] == 'DECLINED'
    assert req(c, r, 'alice')['status'] == 'DECLINED'
    assert 'REQUEST_DECLINED' in kinds(c, 'alice')
    assert quote(c, r['id']).status_code in (409, 422)
    with c.app.state.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Notification)
                         .where(Notification.kind == 'PERSON_RECEIVED')) == 0
