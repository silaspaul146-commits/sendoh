"""Transport contract only: these tests do not assert actual recipient delivery."""
import json
import httpx
import pytest
from app.providers.mesomb import Credentials, MeSombClient, ReconciliationRequired


def deposit(api, **overrides):
    return api.deposit(**(dict(external_id='sendoh-payout-001', amount=1000,
                              receiver='+237600000001', service='MTN') | overrides))


def test_deposit_uses_receiver_and_separate_endpoint_and_reference():
    seen = []
    def handler(request):
        seen.append(request)
        assert request.url.path == '/api/v1.1/payment/deposit/'
        assert request.headers['x-mesomb-trxid'] == 'sendoh-payout-001'
        assert request.headers['authorization'].startswith('HMAC-SHA1 Credential=access/')
        assert json.loads(request.content) == dict(amount=1000, receiver='600000001', service='MTN',
            country='CM', currency='XAF', amount_currency='XAF', conversion=False, trxID='sendoh-payout-001')
        return httpx.Response(202, json={'status': 'PENDING'})
    api = MeSombClient(Credentials('app', 'access', 'secret'), transport=httpx.MockTransport(handler))
    assert deposit(api)['status'] == 'PENDING'
    assert len(seen) == 1


@pytest.mark.parametrize('override', [dict(amount=True),dict(amount=0),dict(amount=1000000001),
    dict(amount=1.5),dict(receiver='+234600000001'),dict(service='OTHER'),dict(external_id='bad&source=X')])
def test_bad_deposit_never_reaches_provider(override):
    def handler(request):
        pytest.fail('Invalid input reached provider')
    api = MeSombClient(Credentials('app', 'access', 'secret'), transport=httpx.MockTransport(handler))
    with pytest.raises(ValueError):
        deposit(api, **override)


@pytest.mark.parametrize('outcome', ['timeout','500','invalid_json'])
def test_ambiguous_deposit_is_not_automatically_repeated(outcome):
    calls = []
    def handler(request):
        calls.append(request)
        if outcome == 'timeout':
            raise httpx.ReadTimeout('unknown', request=request)
        return httpx.Response(500 if outcome == '500' else 200, text='not JSON')
    api = MeSombClient(Credentials('app', 'access', 'secret'), transport=httpx.MockTransport(handler))
    with pytest.raises(ReconciliationRequired):
        deposit(api)
    assert len(calls) == 1
