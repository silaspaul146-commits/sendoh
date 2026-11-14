import time
from sqlalchemy.orm import Session
from app.models import PersonQuote
from test_person_execution import flow
from test_person_orders import prepared
from test_mesomb_lifecycle import client
from test_collections import headers


def test_quote_capability_requires_execution_flag_and_allowed_route(flow, monkeypatch):
    c, r, o = flow
    path = '/api/v1/person-payments/quotes/' + o['quote']['id']
    assert c.get(path, headers=headers('bob')).json()['execution_available'] is True
    monkeypatch.setenv('SENDOH_SANDBOX_PERSON_PAYMENTS', '0')
    assert c.get(path, headers=headers('bob')).json()['execution_available'] is False
    monkeypatch.setenv('SENDOH_SANDBOX_PERSON_PAYMENTS', '1')
    object.__setattr__(c.app.state.mesomb_config, 'test_phones', frozenset())
    assert c.get(path, headers=headers('bob')).json()['execution_available'] is False
    assert c.get('/api/v1/person-payments/orders/' + o['id'], headers=headers('bob')).json()['execution_available'] is False


def test_request_links_exact_execution(flow):
    c, r, o = flow
    before = c.get('/api/v1/money-requests/' + r['id'], headers=headers('bob')).json()
    assert before['payment_order_id'] is None
    assert c.post('/api/v1/person-payments/orders/' + o['id'] + '/execute', headers=headers('bob')).status_code == 200
    for user in ('alice', 'bob'):
        result = c.get('/api/v1/money-requests/' + r['id'], headers=headers(user)).json()
        assert result['payment_order_id'] == o['id']
        assert result['status'] == 'PROCESSING'


def test_expired_quote_never_offers_execution(flow):
    c, r, o = flow
    with Session(c.app.state.engine) as db:
        q = db.get(PersonQuote, o['quote']['id'])
        q.created_at = int(time.time()) - 301
        q.expires_at = int(time.time()) - 1
        db.commit()
    result = c.get('/api/v1/person-payments/quotes/' + o['quote']['id'], headers=headers('bob')).json()
    assert result['expired'] is True
    assert result['execution_available'] is False
