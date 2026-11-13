"""MeSomb transport foundation; intentionally not registered as a public route.

Call collect only after persisting a payment attempt. A timeout is ambiguous:
recover by external reference, never blindly repeat collect. Provider references
are correlation identifiers, not a claimed provider idempotency guarantee.
"""
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import json
import re
import secrets

import httpx
from pymesomb.signature import Signature

BASE_URL = 'https://mesomb.hachther.com/api/v1.1/'


class ReconciliationRequired(Exception):
    """No trustworthy outcome is available. Do not initiate a replacement charge."""


@dataclass(frozen=True)
class Credentials:
    application_key: str = field(repr=False)
    access_key: str = field(repr=False)
    secret_key: str = field(repr=False)

    def __post_init__(self):
        if not all((self.application_key, self.access_key, self.secret_key)):
            raise ValueError('All MeSomb credentials are required.')


def local_phone(phone: str) -> str:
    if not isinstance(phone, str) or not re.fullmatch(r'(?:\+?237)?6[0-9]{8}', phone):
        raise ValueError('Use a Cameroon mobile number in local or +237 format.')
    return phone[-9:]


def reference(value: str) -> str:
    # Restricts query/header characters; persisted Sendoh UUIDs fit this format.
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,120}', value):
        raise ValueError('Invalid Sendoh payment reference.')
    return value


def payment_state(provider_status: str) -> str:
    # CANCELED and ERRORED are not terminal in the published MeSomb contract.
    if not isinstance(provider_status, str):
        raise ReconciliationRequired('Invalid transaction status.')
    return {'SUCCESS': 'SUCCEEDED', 'FAILED': 'FAILED',
            'REFUNDED': 'REFUNDED'}.get(provider_status, 'PENDING')


def validate_transaction(transaction: dict, *, amount: int, service: str,
                         payer: str, provider_id: str | None = None) -> str:
    """Validate a retrieved transaction against persisted payment expectations.

    Caller must also bind it to the external-reference lookup/application and
    apply its result atomically. This helper does not write a ledger.
    """
    if not isinstance(transaction, dict):
        raise ReconciliationRequired('Invalid provider transaction.')
    checks = {}
    try:
        net = Decimal(str(transaction.get('amount')))
        # PAYMENT is the observed sandbox collect response. COLLECT is the
        # documented variant; older COLLECT responses may omit fee details.
        detailed = transaction.get('type') == 'PAYMENT' or any(
            key in transaction for key in ('fees', 'trxamount'))
        if detailed:
            gross = Decimal(str(transaction.get('trxamount')))
            fees = Decimal(str(transaction.get('fees')))
            checks['amount'] = (
                all(value.is_finite() for value in (net, gross, fees))
                and gross == Decimal(amount) and gross > 0
                and net >= 0 and fees >= 0 and net + fees == gross
            )
        else:
            checks['amount'] = net.is_finite() and net == Decimal(amount) and net > 0
    except (ValueError, TypeError, InvalidOperation):
        checks['amount'] = False
    for name, expected in (('currency', 'XAF'), ('country', 'CM'),
                           ('service', service)):
        checks[name] = transaction.get(name) == expected
    checks['type'] = transaction.get('type') in ('COLLECT', 'PAYMENT')
    try:
        checks['payer'] = local_phone(transaction.get('b_party')) == local_phone(payer)
    except (ValueError, TypeError):
        checks['payer'] = False
    pk = transaction.get('pk')
    checks['identifier'] = isinstance(pk, str) and 0 < len(pk) <= 120
    checks['identifier_binding'] = provider_id is None or pk == provider_id
    checks['status'] = isinstance(transaction.get('status'), str) and 0 < len(transaction['status']) <= 40
    if not checks['type']:
        provider_type = transaction.get('type')
        safe_type = (provider_type if isinstance(provider_type, str)
                     and re.fullmatch(r'[A-Za-z_]{1,32}', provider_type)
                     else 'MISSING_OR_INVALID')
        __import__('logging').getLogger(__name__).warning(
            'MESOMB_TYPE expected=COLLECT actual=%s', safe_type)
    failed = [name for name, valid in checks.items() if not valid]
    if failed:
        # Only fixed field names; no provider payload, phone, or credentials.
        raise ReconciliationRequired('FIELD_MISMATCH:' + ','.join(failed))
    return payment_state(transaction['status'])


def collection_amounts(transaction: dict, *, amount: int):
    """Verified collect gross/fee/net evidence; None means unknown, never zero.

    Call only after validate_transaction. Legacy COLLECT responses can confirm
    a contribution but cannot authorize spending net proceeds without fee data.
    """
    if not all(key in transaction for key in ('amount', 'fees', 'trxamount')):
        return None
    try:
        net, fee, gross = (Decimal(str(transaction[key]))
                           for key in ('amount', 'fees', 'trxamount'))
        if (not all(v.is_finite() and v >= 0 and v <= 1_000_000_000
                    and v == v.quantize(Decimal('0.000001')) for v in (net, fee, gross))
                or gross != Decimal(amount) or net + fee != gross):
            raise ValueError()
    except (ValueError, TypeError, InvalidOperation):
        raise ReconciliationRequired('ACCOUNTING_EVIDENCE_INVALID') from None
    return gross, fee, net


def safe_amount_evidence(transaction):
    """Allowlisted numeric evidence only; never log arbitrary provider text."""
    result = {}
    for name in ('amount', 'fees', 'trxamount'):
        value = transaction.get(name)
        if type(value) not in (str, int, float) or len(str(value)) > 32:
            result[name] = 'missing_or_invalid'
            continue
        try:
            number = Decimal(str(value))
            result[name] = str(number) if number.is_finite() else 'invalid'
        except InvalidOperation:
            result[name] = 'invalid'
    return result



class MeSombClient:
    def __init__(self, credentials: Credentials, *, transport=None):
        self.credentials = credentials
        self.transport = transport

    def _request(self, method, endpoint, *, body=None, external_id=None):
        url = BASE_URL + endpoint
        date = datetime.now(timezone.utc)
        nonce = secrets.token_hex(24)
        headers = {
            'X-MeSomb-Application': self.credentials.application_key,
            'x-mesomb-date': str(int(date.timestamp())),
            'x-mesomb-nonce': nonce,
            'Accept': 'application/json',
        }
        signed = None
        if body is not None:
            headers['Content-Type'] = 'application/json'
            signed = {'content-type': 'application/json'}
            headers['X-MeSomb-OperationMode'] = 'asynchronous'
        if external_id is not None:
            headers['X-MeSomb-TrxID'] = reference(external_id)
        headers['Authorization'] = Signature.sign_request(
            'payment', method, url, date, nonce,
            {'access_key': self.credentials.access_key,
             'secret_key': self.credentials.secret_key}, signed, body)
        # Match the SDK's canonical JSON; do not change its global algorithm.
        content = json.dumps(body, separators=(',', ':')).encode() if body is not None else None
        try:
            with httpx.Client(transport=self.transport, timeout=httpx.Timeout(15, connect=5),
                              follow_redirects=False) as client:
                response = client.request(method, url, headers=headers, content=content)
            if not 200 <= response.status_code < 300:
                raise ReconciliationRequired('HTTP_STATUS:' + str(response.status_code))
            return response.json()
        except (httpx.HTTPError, ValueError) as exc:
            # Do not leak provider bodies, credentials or payer details to clients.
            raise ReconciliationRequired('TRANSPORT_OR_JSON_ERROR') from exc

    def collect(self, *, external_id: str, amount: int, payer: str,
                service: str, fees_included: bool):
        if type(amount) is not int or not 0 < amount <= 1_000_000_000:
            raise ValueError('Amount must be a positive whole XAF value within the limit.')
        if service not in ('MTN', 'ORANGE') or type(fees_included) is not bool:
            raise ValueError('Specify the operator and fee treatment explicitly.')
        data = self._request('POST', 'payment/collect/', external_id=reference(external_id), body={
            'amount': amount, 'payer': local_phone(payer), 'service': service,
            'country': 'CM', 'currency': 'XAF', 'amount_currency': 'XAF',
            'conversion': False, 'fees': fees_included,
        })
        if not isinstance(data, dict):
            raise ReconciliationRequired('Invalid provider response.')
        # Initiation response is evidence for recovery, never a ledger write.
        return data

    def deposit(self, *, external_id: str, amount: int, receiver: str, service: str):
        """Internal transport only; caller MUST persist/claim before dispatch.

        SDK 2.1.2 uses receiver and payment/deposit/, moving trxID into the
        X-MeSomb-TrxID header before signing. This is not
        a public payout endpoint or a guarantee of provider idempotency.
        Initiation never proves recipient delivery; resolve by lookup.
        """
        if type(amount) is not int or not 0 < amount <= 1_000_000_000:
            raise ValueError('Amount must be a positive whole XAF value within the limit.')
        if service not in ('MTN', 'ORANGE'):
            raise ValueError('Specify a supported operator.')
        external_id = reference(external_id)
        data = self._request('POST', 'payment/deposit/', external_id=external_id, body={
            'amount': amount, 'receiver': local_phone(receiver), 'service': service,
            'country': 'CM', 'currency': 'XAF', 'amount_currency': 'XAF',
            'conversion': False,
        })
        if not isinstance(data, dict):
            raise ReconciliationRequired('Invalid provider response.')
        return data

    def lookup(self, external_id: str) -> list[dict]:
        data = self._request('GET', 'payment/transactions/?ids=' +
                             reference(external_id) + '&source=EXTERNAL')
        if not isinstance(data, list) or any(not isinstance(item, dict) for item in data):
            raise ReconciliationRequired('LOOKUP_SHAPE_INVALID')
        # Empty is unresolved, not permission to initiate again. Multiple records
        # require investigation; do not pick one arbitrarily.
        return data
