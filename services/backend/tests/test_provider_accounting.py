from decimal import Decimal
import time
import pytest
from sqlalchemy import select, func
from app.models import ProviderPayment, ProviderPaymentEvent
from app.mesomb_payments import reconcile
from app.providers.mesomb import collection_amounts, ReconciliationRequired
from test_mesomb_lifecycle import client, setup, create
from test_collections import headers


def reconcile_details(client, payment_id, fee='20.0', net='980.0'):
    app = client.app
    api = app.state.mesomb_client
    call = next(c for c in api.calls if c['external_id'] == payment_id)
    api.lookup = lambda _: [dict(pk='provider-'+payment_id, status='SUCCESS', type='PAYMENT',
        amount=net, fees=fee, trxamount='1000.0', service=call['service'],
        b_party=call['payer'], country='CM', currency='XAF')]
    with app.state.sessions() as db:
        p = db.get(ProviderPayment, payment_id)
        p.next_check_at = 0
        db.commit()
    reconcile(app.state.sessions, app.state.mesomb_config, api, payment_id)


def test_confirmed_gross_fee_net_persist_once_and_conflict_is_not_overwritten(client):
    c, _ = setup(client)
    response = create(client, c)
    pid = response.json()['id']
    reconcile_details(client, pid)
    with client.app.state.sessions() as db:
        p = db.get(ProviderPayment, pid)
        assert p.status == 'SUCCEEDED'
        assert (p.confirmed_gross, p.confirmed_provider_fee, p.confirmed_net) == (Decimal(1000), Decimal(20), Decimal(980))
        original_time = p.accounting_verified_at
    reconcile_details(client, pid)
    reconcile_details(client, pid, fee='30', net='970')
    with client.app.state.sessions() as db:
        p = db.get(ProviderPayment, pid)
        assert p.confirmed_net == Decimal(980)
        assert p.accounting_verified_at == original_time
        assert p.review_reason == 'CONFLICTING_PROVIDER_ACCOUNTING'
        assert db.scalar(select(func.count()).select_from(ProviderPaymentEvent).where(ProviderPaymentEvent.payment_id == pid, ProviderPaymentEvent.status == 'SUCCEEDED')) == 1
    result = client.get('/api/v1/provider-payments/'+pid, headers=headers('bob')).json()
    assert result['accounting']['verified'] is True
    assert Decimal(result['accounting']['provider_fee']) == 20
    assert result['accounting']['recipient_delivery_confirmed'] is False


def test_legacy_success_does_not_invent_zero_fees(client):
    c, _ = setup(client)
    pid = create(client, c).json()['id']
    app = client.app
    with app.state.sessions() as db:
        p = db.get(ProviderPayment, pid); p.next_check_at = 0; db.commit()
    reconcile(app.state.sessions, app.state.mesomb_config, app.state.mesomb_client, pid)
    with app.state.sessions() as db:
        p = db.get(ProviderPayment, pid)
        assert p.status == 'SUCCEEDED'
        assert p.accounting_verified_at is None
        assert p.confirmed_provider_fee is None
    # A later detailed lookup may enrich, but never duplicate, a success.
    reconcile_details(client, pid)
    with app.state.sessions() as db:
        assert db.get(ProviderPayment, pid).confirmed_net == Decimal(980)


@pytest.mark.parametrize('details', [dict(amount='980',fees='-20',trxamount='1000'),
    dict(amount='980',fees='NaN',trxamount='1000'),
    dict(amount='980',fees='21',trxamount='1000'),
    dict(amount='979.9999999',fees='20.0000001',trxamount='1000')])
def test_invalid_accounting_rejected(details):
    with pytest.raises(ReconciliationRequired):
        collection_amounts(details, amount=1000)
