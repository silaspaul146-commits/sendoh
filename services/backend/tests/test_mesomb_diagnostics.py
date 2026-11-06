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
        validate_transaction(tx(amount=980, fees=20, trxamount=1000),
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
