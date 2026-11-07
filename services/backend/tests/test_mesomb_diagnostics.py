import pytest
from app.providers.mesomb import validate_transaction, ReconciliationRequired, safe_amount_evidence

def tx(**changes):
    return dict(pk='provider-1', amount=1000, currency='XAF', country='CM',
                service='MTN', type='COLLECT', b_party='600000001', status='SUCCESS') | changes

@pytest.mark.parametrize('phone', ['600000001', '+237600000001', '237600000001'])
def test_equivalent_payer_formats(phone):
    assert validate_transaction(tx(b_party=phone), amount=1000, service='MTN',
                                payer='+237600000001') == 'SUCCEEDED'

def test_net_amount_is_not_silently_credited():
    with pytest.raises(ReconciliationRequired, match='FIELD_MISMATCH:amount'):
        validate_transaction(tx(amount=980, fees=20, trxamount=999),
                             amount=1000, service='MTN', payer='600000001')

def test_wrong_payer_remains_rejected_without_phone_in_error():
    with pytest.raises(ReconciliationRequired) as error:
        validate_transaction(tx(b_party='237600000002'), amount=1000,
                             service='MTN', payer='600000001')
    assert str(error.value) == 'FIELD_MISMATCH:payer'

def test_numeric_evidence_excludes_provider_secrets_and_arbitrary_text():
    assert safe_amount_evidence(dict(amount=980, fees=20, trxamount='secret',
                                    phone='600000001', token='secret')) == {
        'amount': '980', 'fees': '20', 'trxamount': 'invalid'}

def test_missing_fields_report_precise_checks():
    with pytest.raises(ReconciliationRequired, match='identifier,status'):
        validate_transaction(tx(pk=None, status=None), amount=1000,
                             service='MTN', payer='600000001')


@pytest.mark.parametrize('kind', ['PAYMENT', 'COLLECT'])
def test_gross_contribution_with_provider_fee(kind):
    assert validate_transaction(tx(type=kind, amount='980.0', fees='20.0',
        trxamount='1000.0'), amount=1000, service='MTN',
        payer='600000001') == 'SUCCEEDED'

@pytest.mark.parametrize('changes', [
    dict(trxamount=999), dict(amount=979), dict(fees=-20, amount=1020),
    dict(amount=-1, fees=1001), dict(fees=None), dict(trxamount=None),
    dict(amount='NaN'), dict(fees='Infinity'), dict(type='DEPOSIT'),
    dict(b_party='600000002'), dict(service='ORANGE'), dict(currency='EUR'),
    dict(country='NG'), dict(pk=None),
])
def test_payment_payload_mismatches_never_credit(changes):
    with pytest.raises(ReconciliationRequired):
        validate_transaction(tx(type='PAYMENT', amount=980, fees=20,
            trxamount=1000) | changes, amount=1000, service='MTN',
            payer='600000001')

def test_payment_requires_gross_and_fee_evidence():
    with pytest.raises(ReconciliationRequired):
        validate_transaction(tx(type='PAYMENT'), amount=1000, service='MTN',
                             payer='600000001')
