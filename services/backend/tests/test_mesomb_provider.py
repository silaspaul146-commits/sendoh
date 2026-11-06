"""Provider contract tests using an intercepted transport. No real SMS or money."""
import json
import httpx
import pytest
from app.providers.mesomb import (
    Credentials, MeSombClient, ReconciliationRequired, payment_state,
    validate_transaction,
)


def client(handler):
    return MeSombClient(Credentials('app-test', 'access-test', 'secret-test'),
                        transport=httpx.MockTransport(handler))


def collect(api, **overrides):
    args = dict(external_id='sendoh-attempt-001', amount=1000,
                payer='+237670000000', service='MTN', fees_included=True)
    return api.collect(**(args | overrides))


def test_wire_contract_and_lookup_after_initiation():
    requests = []
    def handler(request):
        requests.append(request)
        assert request.url.host == 'mesomb.hachther.com'
        assert request.headers['x-mesomb-application'] == 'app-test'
        assert request.headers['authorization'].startswith('HMAC-SHA1 Credential=access-test/')
        assert request.extensions['timeout']['read'] == 15
        assert request.extensions['timeout']['connect'] == 5
        if request.method == 'POST':
            assert request.url.path == '/api/v1.1/payment/collect/'
            assert request.headers['x-mesomb-trxid'] == 'sendoh-attempt-001'
            assert request.headers['x-mesomb-operationmode'] == 'asynchronous'
            data = json.loads(request.content)
            assert data == dict(amount=1000, payer='670000000', service='MTN', fees=True,
                                country='CM', currency='XAF', amount_currency='XAF', conversion=False)
            return httpx.Response(202, json={'success': True, 'status': 'PENDING'})
        assert request.url.params['source'] == 'EXTERNAL'
        assert request.url.params['ids'] == 'sendoh-attempt-001'
        return httpx.Response(200, json=[])
    api = client(handler)
    assert collect(api)['status'] == 'PENDING'
    assert api.lookup('sendoh-attempt-001') == []
    assert len(requests) == 2
    assert requests[0].headers['x-mesomb-nonce'] != requests[1].headers['x-mesomb-nonce']


@pytest.mark.parametrize('outcome', ['timeout', 'disconnect', 'invalid_json', 'redirect', 'server_error'])
def test_ambiguous_outcome_never_retries_collect(outcome):
    calls = []
    def handler(request):
        calls.append(request)
        if outcome == 'timeout':
            raise httpx.ReadTimeout('uncertain', request=request)
        if outcome == 'disconnect':
            raise httpx.RemoteProtocolError('connection closed', request=request)
        if outcome == 'invalid_json':
            return httpx.Response(200, text='not JSON')
        if outcome == 'redirect':
            return httpx.Response(302, headers={'location': 'https://example.com'})
        return httpx.Response(500, text='internal provider details')
    with pytest.raises(ReconciliationRequired):
        collect(client(handler))
    assert len(calls) == 1


@pytest.mark.parametrize('status', ['PENDING', 'ONGOING', 'COLLECTED', 'CANCELED',
                                  'ERRORED', 'STOPPED', 'WAITING_VALIDATION', 'NEW_STATUS'])
def test_nonfinal_status_never_fulfils_obligation(status):
    assert payment_state(status) == 'PENDING'


@pytest.mark.parametrize('override', [dict(amount=True), dict(amount=0), dict(amount=1.5),
    dict(service='UNKNOWN'), dict(payer='+234670000000'), dict(fees_included=None),
    dict(external_id='attempt&source=MESOMB')])
def test_invalid_input_cannot_reach_provider(override):
    def handler(request):
        pytest.fail('Invalid request reached provider')
    with pytest.raises(ValueError):
        collect(client(handler), **override)


def transaction():
    return dict(pk='mesomb-001', amount=1000, country='CM', currency='XAF',
                service='MTN', type='COLLECT', b_party='670000000', status='SUCCESS')


@pytest.mark.parametrize('override', [dict(amount=999), dict(currency='EUR'), dict(country='NG'),
    dict(service='ORANGE'), dict(type='DEPOSIT'), dict(b_party='690000001'), dict(pk='other'),
    dict(amount='NaN'), dict(amount=None)])
def test_success_for_wrong_payment_is_rejected(override):
    with pytest.raises(ReconciliationRequired):
        validate_transaction(transaction() | override, amount=1000, service='MTN',
                             payer='+237670000000', provider_id='mesomb-001')


@pytest.mark.parametrize(('status', 'expected'), [('SUCCESS', 'SUCCEEDED'),
    ('FAILED', 'FAILED'), ('REFUNDED', 'REFUNDED'), ('COLLECTED', 'PENDING')])
def test_verified_outcomes(status, expected):
    assert validate_transaction(transaction() | {'status': status}, amount=1000,
        service='MTN', payer='+237670000000', provider_id='mesomb-001') == expected


def test_credentials_not_in_repr():
    assert 'secret-test' not in repr(Credentials('app-test', 'access-test', 'secret-test'))
