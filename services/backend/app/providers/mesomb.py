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
    if not isinstance(phone, str) or not re.fullmatch(r'(?:\+237)?6[0-9]{8}', phone):
        raise ValueError('Use a Cameroon mobile number in local or +237 format.')
    return phone.removeprefix('+237')


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
    try:
        actual_amount = Decimal(str(transaction['amount']))
        matches = (
            actual_amount.is_finite() and actual_amount == Decimal(amount)
            and transaction['currency'] == 'XAF'
            and transaction['country'] == 'CM'
            and transaction['service'] == service
            and transaction['type'] == 'COLLECT'
            and local_phone(transaction['b_party']) == local_phone(payer)
            and isinstance(transaction['pk'], str) and bool(transaction['pk'])
            and (provider_id is None or transaction['pk'] == provider_id)
        )
    except (KeyError, ValueError, TypeError, InvalidOperation):
        matches = False
    if not matches:
        raise ReconciliationRequired('Provider transaction does not match the payment.')
    return payment_state(transaction.get('status'))


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
                raise ReconciliationRequired('Provider response requires reconciliation.')
            return response.json()
        except (httpx.HTTPError, ValueError) as exc:
            # Do not leak provider bodies, credentials or payer details to clients.
            raise ReconciliationRequired('Provider outcome could not be established.') from exc

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

    def lookup(self, external_id: str) -> list[dict]:
        data = self._request('GET', 'payment/transactions/?ids=' +
                             reference(external_id) + '&source=EXTERNAL')
        if not isinstance(data, list) or any(not isinstance(item, dict) for item in data):
            raise ReconciliationRequired('Invalid transaction lookup response.')
        # Empty is unresolved, not permission to initiate again. Multiple records
        # require investigation; do not pick one arbitrarily.
        return data
