"""Sandbox collection payments shared by authenticated Flutter and guest actors.

Persist before dispatch. Dispatch exactly once in this process; after any crash or
uncertain response only GET reconciliation is permitted. No client-set outcome.
"""
import asyncio
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
import hashlib
import hmac
import json
import logging
import os
import re
import time
import uuid

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import select, update, func, or_, and_
from sqlalchemy.exc import IntegrityError

from .models import (User, Collection, Participant, PhoneIdentity, Activity,
                     ProviderPayment as Payment, ProviderPaymentEvent, MeSombWebhook)
from .providers.mesomb import Credentials, MeSombClient, ReconciliationRequired, local_phone, validate_transaction, safe_amount_evidence, collection_amounts

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class PaymentConfig:
    credentials: Credentials = field(repr=False)
    webhook_secret: str = field(repr=False)
    test_phones: frozenset[str]
    application_hash: str


def configuration(settings):
    mode = os.getenv('SENDOH_MESOMB_MODE', 'disabled')
    if mode == 'disabled':
        return None
    if mode != 'sandbox' or settings.environment == 'production':
        raise RuntimeError('This increment permits MeSomb sandbox only, outside production.')
    if os.getenv('MESOMB_SANDBOX_CONFIRMED') != '1':
        raise RuntimeError('Confirm that these credentials belong to an authorized MeSomb test application.')
    names = ('MESOMB_APPLICATION_KEY', 'MESOMB_ACCESS_KEY', 'MESOMB_SECRET_KEY', 'MESOMB_WEBHOOK_SECRET')
    if any(not os.getenv(n) for n in names):
        raise RuntimeError('Missing MeSomb sandbox credentials or webhook secret.')
    phones = frozenset(local_phone(p.strip()) for p in os.getenv('MESOMB_TEST_PHONES', '').split(',') if p.strip())
    if not phones:
        raise RuntimeError('MESOMB_TEST_PHONES must contain documented MeSomb sandbox numbers.')
    creds = Credentials(*(os.environ[n] for n in names[:3]))
    return PaymentConfig(creds, os.environ[names[3]], phones,
                         hashlib.sha256(creds.application_key.encode()).hexdigest())


class Intent(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    collection_id: str | None = Field(default=None, min_length=36, max_length=36)
    collection_token: str | None = Field(default=None, min_length=1, max_length=80)
    amount: int = Field(strict=True, gt=0, le=1_000_000_000)
    method: str = Field(pattern='^(MTN|ORANGE)$')
    payer_phone: str

    @model_validator(mode='after')
    def target(self):
        if (self.collection_id is None) == (self.collection_token is None):
            raise ValueError('Supply exactly one collection identifier.')
        self.payer_phone = local_phone(self.payer_phone)
        return self


def view(p):
    return dict(id=p.id, reference=p.id, mode='SANDBOX', provider='MESOMB',
                purpose='COLLECTION_CONTRIBUTION', collection_id=p.collection_id,
                participant_id=p.participant_id, payer_id=p.payer_id,
                beneficiary_id=p.beneficiary_id, amount=p.amount, currency='XAF',
                method=p.method, status=p.status, provider_status=p.provider_status,
                reconciliation_required=p.status == 'PENDING' or p.review_reason is not None,
                review_reason=p.review_reason, created_at=p.created_at, updated_at=p.updated_at,
                receipt_available=p.status == 'SUCCEEDED',
                accounting=dict(verified=p.accounting_verified_at is not None,
                    gross=str(p.confirmed_gross) if p.confirmed_gross is not None else None,
                    provider_fee=str(p.confirmed_provider_fee) if p.confirmed_provider_fee is not None else None,
                    net=str(p.confirmed_net) if p.confirmed_net is not None else None,
                    currency='XAF', verified_at=p.accounting_verified_at,
                    recipient_delivery_confirmed=False),
                notice='MeSomb sandbox transaction. No real money moved. Not proof of live payment.')


def sandbox_total(db, collection_id, participant_id=None):
    q = select(func.coalesce(func.sum(Payment.amount), 0)).where(
        Payment.collection_id == collection_id, Payment.status == 'SUCCEEDED', Payment.mode == 'SANDBOX')
    if participant_id:
        q = q.where(Payment.participant_id == participant_id)
    return int(db.scalar(q))


def reconcile(sessions, config, api, payment_id):
    """Lease work across processes, query outside a transaction, apply atomically."""
    now = int(time.time())
    owner = str(uuid.uuid4())
    with sessions() as db:
        claim = db.execute(update(Payment).where(Payment.id == payment_id,
            Payment.application_hash == config.application_hash, Payment.lease_until <= now,
            Payment.next_check_at <= now).values(lease_owner=owner, lease_until=now + 90))
        db.commit()
        if claim.rowcount != 1:
            return
        p = db.get(Payment, payment_id)
        expected = dict(amount=p.amount, service=p.method, payer=p.payer_phone, provider_id=p.provider_id)
    transaction = None
    reason = None
    desired = None
    amounts = None
    try:
        rows = api.lookup(payment_id)
        if len(rows) != 1:
            reason = 'NO_MATCH_YET' if not rows else 'MULTIPLE_PROVIDER_MATCHES'
        else:
            transaction = rows[0]
            desired = validate_transaction(transaction, **expected)
            if desired == 'SUCCEEDED':
                amounts = collection_amounts(transaction, amount=expected['amount'])
            if len(transaction['pk']) > 120 or len(str(transaction.get('status', ''))) > 40:
                raise ReconciliationRequired('Malformed provider identifier/status.')
    except ReconciliationRequired as exc:
        reason = 'PROVIDER_UNVERIFIED'
        logger.warning('MESOMB_DIAGNOSTIC attempt=%s check=%s amounts=%s',
                       payment_id, str(exc),
                       safe_amount_evidence(transaction) if isinstance(transaction, dict) else {})
    except Exception:
        # Unexpected SDK/transport behaviour must not result in a new debit.
        reason = 'RECONCILIATION_ERROR'
        logger.warning('MeSomb reconciliation failed for attempt %s', payment_id)
    with sessions() as db:
        p = db.scalar(select(Payment).where(Payment.id == payment_id,
            Payment.lease_owner == owner).with_for_update())
        if p is None:
            return
        p.attempts += 1
        p.updated_at = int(time.time())
        p.review_reason = reason
        if amounts is not None and p.accounting_verified_at is not None:
            saved = (p.confirmed_gross, p.confirmed_provider_fee, p.confirmed_net)
            if saved != amounts:
                reason = 'CONFLICTING_PROVIDER_ACCOUNTING'
                p.review_reason = reason
        if desired is not None and reason is None:
            transitions = {'PENDING': {'PENDING','SUCCEEDED','FAILED','REFUNDED'},
                           'SUCCEEDED': {'SUCCEEDED','REFUNDED'}, 'FAILED': {'FAILED'},
                           'REFUNDED': {'REFUNDED'}}
            if desired not in transitions[p.status]:
                p.review_reason = 'CONFLICTING_PROVIDER_OUTCOME'
            else:
                if desired == 'SUCCEEDED' and amounts is not None and p.accounting_verified_at is None:
                    p.confirmed_gross, p.confirmed_provider_fee, p.confirmed_net = amounts
                    p.accounting_verified_at = p.updated_at
                p.provider_id = transaction['pk']
                p.provider_status = transaction['status']
                if desired != p.status:
                    p.status = desired
                    db.add(ProviderPaymentEvent(payment_id=p.id, status=desired, created_at=p.updated_at))
                    # Existing activity contract; push presentation remains a later client change.
                    db.add(Activity(organizer_id=p.beneficiary_id, collection_id=p.collection_id,
                        message=f'MeSomb sandbox contribution {p.id}: {desired.lower()} ({p.amount} FCFA; no real money).'))
        delay = min(3600, 15 * 2 ** min(p.attempts, 8)) if p.status == 'PENDING' else 86400
        p.next_check_at = p.updated_at + delay
        p.lease_until = 0
        p.lease_owner = None
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            # A provider ID already belonging to another payment cannot be credited.
            db.execute(update(Payment).where(Payment.id == payment_id, Payment.lease_owner == owner)
                .values(review_reason='DUPLICATE_PROVIDER_TRANSACTION', lease_until=0,
                        lease_owner=None, next_check_at=int(time.time()) + 3600))
            db.commit()


def run_due(sessions, config, api):
    with sessions() as db:
        ids = list(db.scalars(select(Payment.id).where(Payment.application_hash == config.application_hash,
            Payment.next_check_at <= int(time.time()), Payment.lease_until <= int(time.time()))
            .order_by(Payment.next_check_at).limit(20)))
    for payment_id in ids:
        reconcile(sessions, config, api, payment_id)


def lifespan_with_payments(base_lifespan, sessions, config):
    @asynccontextmanager
    async def lifespan(app):
        async with base_lifespan(app):
            stop = asyncio.Event()
            async def worker():
                while not stop.is_set():
                    try:
                        await asyncio.to_thread(run_due, sessions, config, app.state.mesomb_client)
                    except Exception:
                        logger.warning('MeSomb reconciliation sweep failed; retrying on next sweep.')
                    try:
                        await asyncio.wait_for(stop.wait(), timeout=15)
                    except asyncio.TimeoutError:
                        pass
            task = asyncio.create_task(worker()) if config else None
            try:
                yield
            finally:
                stop.set()
                if task:
                    await task
    return lifespan


def verify_webhook(raw, headers, secret):
    try:
        parts = dict(item.strip().split('=', 1) for item in headers.get('x-mesomb-webhook-signature', '').split(','))
        stamp = parts['t']
        if not re.fullmatch(r'[0-9]{10}', stamp) or abs(int(time.time()) - int(stamp)) > 300:
            raise ValueError()
        if headers.get('x-mesomb-webhook-request-timestamp') != stamp:
            raise ValueError()
        expected = hmac.new(secret.encode(), stamp.encode() + b'.' + raw, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected, parts['v1']):
            raise ValueError()
        payload = json.loads(raw)
        event_id = payload['id']
        if not isinstance(event_id, str) or not 1 <= len(event_id) <= 160:
            raise ValueError()
        if headers.get('x-mesomb-webhook-event-id') != event_id:
            raise ValueError()
        if not isinstance(payload.get('type'), str) or len(payload['type']) > 120:
            raise ValueError()
        return payload
    except (ValueError, KeyError, TypeError):
        raise HTTPException(400, 'Invalid webhook signature or envelope.')


def router(database, actor, sessions, config):
    routes = APIRouter(prefix='/api/v1')

    def require_enabled():
        if config is None:
            raise HTTPException(403, 'MeSomb sandbox payments are disabled.')

    def owned(db, payment_id, user):
        p = db.get(Payment, payment_id)
        if p is None or user.id not in (p.payer_id, p.beneficiary_id):
            raise HTTPException(404, 'Payment not found.')
        return p

    @routes.post('/provider-payments', status_code=201)
    def create(data: Intent, request: Request,
               idempotency_key: str = Header(min_length=8, max_length=120),
               user=Depends(actor), db=Depends(database)):
        require_enabled()
        if data.payer_phone not in config.test_phones:
            raise HTTPException(422, 'Use an approved MeSomb sandbox test number.')
        db.scalar(select(User).where(User.id == user.id).with_for_update())
        digest = hashlib.sha256(json.dumps(data.model_dump(), sort_keys=True).encode()).hexdigest()
        existing = db.scalar(select(Payment).where(Payment.payer_id == user.id, Payment.request_key == idempotency_key))
        if existing:
            if existing.fingerprint != digest:
                raise HTTPException(409, 'Request key already used with different details.')
            return view(existing)
        if not user.display_name or not db.scalar(select(PhoneIdentity.phone).where(PhoneIdentity.user_id == user.id)):
            raise HTTPException(403, 'Verify your identity before contributing.')
        recent = db.scalar(select(func.count()).select_from(Payment).where(Payment.payer_id == user.id,
            Payment.created_at > int(time.time()) - 3600))
        if recent >= 20:
            raise HTTPException(429, 'Payment attempt limit reached. Try later.')
        target = Collection.id == data.collection_id if data.collection_id else Collection.public_token == data.collection_token
        c = db.scalar(select(Collection).where(target).with_for_update())
        if c is None or c.status != 'ACTIVE':
            raise HTTPException(404, 'Active collection not found.')
        member = db.scalar(select(Participant).where(Participant.collection_id == c.id, Participant.user_id == user.id))
        if member is None and c.organizer_id == user.id:
            member = Participant(collection_id=c.id, user_id=user.id, name=user.display_name,
                                 expected_amount=c.expected_amount, invitation_state='ACCEPTED')
            db.add(member)
            db.flush()
        if member is None or member.invitation_state != 'ACCEPTED':
            raise HTTPException(403, 'Join this collection before contributing.')
        pending = db.scalar(select(Payment.id).where(Payment.payer_id == user.id,
            Payment.collection_id == c.id, Payment.status == 'PENDING'))
        if pending:
            raise HTTPException(409, 'An earlier payment is unresolved. Check its status before starting another.')
        if c.mode == 'MINIMUM_TOTAL' and sandbox_total(db, c.id, member.id) + data.amount < (member.expected_amount or c.expected_amount or 0):
            raise HTTPException(422, 'Contribution does not meet the outstanding minimum.')
        now = int(time.time())
        p = Payment(collection_id=c.id, participant_id=member.id, payer_id=user.id,
                    beneficiary_id=c.organizer_id, request_key=idempotency_key, fingerprint=digest,
                    application_hash=config.application_hash, amount=data.amount, method=data.method,
                    payer_phone=data.payer_phone, created_at=now, updated_at=now, next_check_at=now+30)
        db.add(p)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            existing = db.scalar(select(Payment).where(Payment.payer_id == user.id, Payment.request_key == idempotency_key))
            if existing and existing.fingerprint == digest:
                return view(existing)
            raise HTTPException(409, 'Payment changed. Refresh before retrying.')
        # The record is durable before dispatch. Even a process crash now does not
        # permit a retrying request to issue a second provider call.
        try:
            request.app.state.mesomb_client.collect(external_id=p.id, amount=p.amount,
                payer=p.payer_phone, service=p.method, fees_included=True)
        except Exception:
            p.review_reason = 'INITIATION_UNCERTAIN'
            db.commit()
        # Initiation alone cannot credit an obligation, even if it says SUCCESS.
        return view(p)

    @routes.get('/provider-payments/{payment_id}')
    def detail(payment_id: str, user=Depends(actor), db=Depends(database)):
        return view(owned(db, payment_id, user))

    @routes.get('/me/provider-payments')
    def history(collection_token: str | None = None, before: str | None = None,
                payer_only: bool = False, user=Depends(actor), db=Depends(database)):
        access = (Payment.payer_id == user.id if payer_only else
                  or_(Payment.payer_id == user.id, Payment.beneficiary_id == user.id))
        query = select(Payment).where(access)
        if collection_token is not None:
            collection_id = db.scalar(select(Collection.id).where(
                Collection.public_token == collection_token))
            if collection_id is None:
                raise HTTPException(404, 'Collection not found.')
            query = query.where(Payment.collection_id == collection_id)
        if before is not None:
            cursor = db.scalar(query.where(Payment.id == before))
            if cursor is None:
                raise HTTPException(404, 'Payment cursor not found.')
            query = query.where(or_(Payment.created_at < cursor.created_at,
                and_(Payment.created_at == cursor.created_at, Payment.id < cursor.id)))
        rows = list(db.scalars(query.order_by(
            Payment.created_at.desc(), Payment.id.desc()).limit(101)))
        page = rows[:100]
        return dict(items=[view(p) for p in page], limit=100,
                    next_cursor=page[-1].id if len(rows) > 100 else None)

    @routes.post('/provider-payments/{payment_id}/refresh')
    def refresh(payment_id: str, request: Request, user=Depends(actor), db=Depends(database)):
        require_enabled()
        p = owned(db, payment_id, user)
        db.commit()
        reconcile(sessions, config, request.app.state.mesomb_client, p.id)
        db.expire_all()
        return view(owned(db, payment_id, user))

    @routes.post('/webhooks/mesomb')
    async def webhook(request: Request, db=Depends(database)):
        require_enabled()
        raw = await request.body()
        if len(raw) > 65536:
            raise HTTPException(413, 'Webhook too large.')
        payload = verify_webhook(raw, request.headers, config.webhook_secret)
        digest = hashlib.sha256(raw).hexdigest()
        existing = db.get(MeSombWebhook, payload['id'])
        if existing:
            if existing.body_hash != digest:
                raise HTTPException(409, 'Webhook ID reused with a different payload.')
            return {'received': True}
        db.add(MeSombWebhook(event_id=payload['id'], body_hash=digest,
                             event_type=payload['type'], received_at=int(time.time())))
        # Callback is a wake-up signal, not an accounting authority. Re-read from
        # the configured application by each persisted external reference.
        data = payload.get('data')
        obj = data.get('object') if isinstance(data, dict) else None
        provider_id = obj.get('pk') if isinstance(obj, dict) else None
        condition = Payment.status == 'PENDING'
        if isinstance(provider_id, str):
            condition = or_(condition, Payment.provider_id == provider_id)
        try:
            db.execute(update(Payment).where(Payment.application_hash == config.application_hash,
                condition).values(next_check_at=int(time.time())))
            db.commit()
        except IntegrityError:
            db.rollback()
            existing = db.get(MeSombWebhook, payload['id'])
            if not existing or existing.body_hash != digest:
                raise HTTPException(409, 'Conflicting webhook event.')
        return {'received': True}
    return routes
