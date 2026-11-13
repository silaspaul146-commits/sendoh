"""Expiring sandbox quotes and durable orders; dispatch is deliberately absent.

An order is explicit consent to the quoted terms, NOT proof of payment. Neither
route may collect, deposit or set a request paid. The next execution increment
must claim/commit collection and delivery independently before external calls.
"""
import time
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select, update, func
from sqlalchemy.exc import IntegrityError

from .models import User, MoneyRequest, PersonQuote, PersonOrder, ReceivingDestination, PersonExecution
from .receiving import Preflight, identity_phone, current_destination, destination_current
from .people import state, person
from .fee_quotes import configured_policy, calculate
from .person_execution_state import request_execution, enabled


class QuoteInput(Preflight):
    payer_method: Literal['MTN', 'ORANGE']


class AcceptQuote(BaseModel):
    model_config = ConfigDict(extra='forbid')
    quote_id: str = Field(min_length=36, max_length=36)
    consent: Literal['ACCEPT_QUOTED_TOTAL']


def quote_view(db, q):
    d = db.get(ReceivingDestination, q.destination_id)
    return dict(id=q.id, purpose='REQUEST_PAYMENT' if q.request_id else 'PERSON_PAYMENT',
        request_id=q.request_id, recipient=person(db.get(User, q.beneficiary_id)),
        payer_method=q.payer_method, receiving_method=d.method,
        amounts=q.amounts, fee_policy_version=q.policy['version'],
        created_at=q.created_at, expires_at=q.expires_at,
        expired=q.expires_at <= int(time.time()), mode='SANDBOX', execution_available=False)


def order_view(db, o, config=None):
    from .person_execution import execution_view
    execution = execution_view(db, o.id)
    result = dict(id=o.id, quote=quote_view(db, db.get(PersonQuote, o.quote_id)),
        status='EXPIRED' if o.status == 'READY' and o.expires_at <= int(time.time()) else o.status,
        collection_status=o.collection_status, delivery_status=o.delivery_status,
        receipt_available=False, execution_available=bool(enabled(config) and not execution
            and o.status == 'READY' and o.expires_at > int(time.time())
            and db.get(PersonQuote, o.quote_id).amounts['delivery_fee'] == 0),
        created_at=o.created_at, expires_at=o.expires_at)
    if execution:
        result.update(status=execution['state'], collection_status=execution['collection_status'],
            delivery_status=execution['delivery_status'], receipt_available=execution['recipient_delivery_confirmed'],
            execution=execution)
    return result


def router(database, actor, config):
    routes = APIRouter(prefix='/api/v1/person-payments')

    def policy():
        p = configured_policy()
        if config is None or p is None:
            raise HTTPException(503, 'Payment quoting is not configured.')
        return p

    def payable(db, request_id, payer_id, lock=False):
        query = select(MoneyRequest).where(MoneyRequest.id == request_id)
        if lock:
            query = query.with_for_update()
        r = db.scalar(query.execution_options(populate_existing=True))
        if r is None or r.recipient_id != payer_id:
            raise HTTPException(404, 'Payable request not found.')
        if request_execution(db, r.id):
            raise HTTPException(409, 'This request already has a payment in progress or completed.')
        if state(r) != 'PENDING':
            raise HTTPException(409, 'This request is no longer payable.')
        return r

    @routes.post('/quotes', status_code=201)
    def create_quote(data: QuoteInput, user=Depends(actor), db=Depends(database)):
        p = policy()
        # Serialize per-payer quote rate limit, including concurrent requests.
        db.scalar(select(User).where(User.id == user.id).with_for_update())
        phone = identity_phone(db, user.id)
        if not phone or not user.username or not user.display_name:
            raise HTTPException(409, 'Complete your phone identity and profile first.')
        r = payable(db, data.request_id, user.id) if data.request_id else None
        beneficiary_id = r.requester_id if r else data.recipient_id
        amount = r.amount if r else data.amount
        recipient = db.get(User, beneficiary_id)
        if recipient is None or not recipient.username or not recipient.display_name:
            raise HTTPException(404, 'Recipient unavailable.')
        if beneficiary_id == user.id:
            raise HTTPException(409, 'Choose another person.')
        d = current_destination(db, beneficiary_id)
        if not destination_current(db, d):
            raise HTTPException(409, 'The recipient must confirm their receiving details.')
        now = int(time.time())
        if r and r.expires_at is not None and r.expires_at <= now:
            raise HTTPException(409, 'This request has expired.')
        count = db.scalar(select(func.count()).select_from(PersonQuote).where(
            PersonQuote.payer_id == user.id, PersonQuote.created_at > now - 3600))
        if count >= 60:
            raise HTTPException(429, 'Quote limit reached. Try later.')
        try:
            amounts = calculate(amount, p)
        except ValueError:
            raise HTTPException(422, 'Amount and fees exceed the payment limit.') from None
        q = PersonQuote(payer_id=user.id, beneficiary_id=beneficiary_id,
            request_id=r.id if r else None, destination_id=d.id,
            application_hash=config.application_hash, policy_hash=p.fingerprint,
            policy=p.model_dump(), amounts=amounts, payer_phone=phone,
            payer_method=data.payer_method, created_at=now,
            expires_at=min(now + 300, r.expires_at) if r and r.expires_at else now + 300)
        db.add(q)
        db.commit()
        return quote_view(db, q)

    @routes.get('/quotes/{id}')
    def get_quote(id: str, user=Depends(actor), db=Depends(database)):
        q = db.get(PersonQuote, id)
        if q is None or q.payer_id != user.id:
            raise HTTPException(404, 'Quote not found.')
        return quote_view(db, q)

    @routes.post('/orders', status_code=201)
    def accept(data: AcceptQuote, idempotency_key: str = Header(min_length=8, max_length=120),
               user=Depends(actor), db=Depends(database)):
        # Recover committed orders even if policy/configuration later changed.
        old = db.scalar(select(PersonOrder).where(PersonOrder.payer_id == user.id,
            PersonOrder.request_key == idempotency_key))
        if old:
            if old.quote_id != data.quote_id:
                raise HTTPException(409, 'This payment key belongs to different details.')
            return order_view(db, old, config)
        q = db.get(PersonQuote, data.quote_id)
        if q is None or q.payer_id != user.id:
            raise HTTPException(404, 'Quote not found.')
        # Consistent user lock ordering avoids cross-payment deadlocks and
        # serializes destination consent changes with order acceptance.
        list(db.scalars(select(User).where(User.id.in_([user.id, q.beneficiary_id]))
            .order_by(User.id).with_for_update()))
        old = db.scalar(select(PersonOrder).where(PersonOrder.quote_id == q.id))
        if old:
            if old.request_key == idempotency_key:
                return order_view(db, old, config)
            raise HTTPException(409, 'This quote already has an order. Resume that order.')
        p = policy()
        now = int(time.time())
        if q.expires_at <= now:
            raise HTTPException(409, 'Quote expired. Review a new quote.')
        if q.policy_hash != p.fingerprint or q.application_hash != config.application_hash:
            raise HTTPException(409, 'Payment terms changed. Review a new quote.')
        if identity_phone(db, user.id) != q.payer_phone:
            raise HTTPException(409, 'Your phone identity changed. Review a new quote.')
        d = current_destination(db, q.beneficiary_id)
        if not destination_current(db, d) or d.id != q.destination_id:
            raise HTTPException(409, 'Receiving details changed. Review a new quote.')
        r = payable(db, q.request_id, user.id, lock=True) if q.request_id else None
        if r and (r.requester_id != q.beneficiary_id or r.amount != q.amounts['recipient_amount']):
            raise HTTPException(409, 'Request details changed. Review a new quote.')
        if r:
            # Also acquires a write lock on SQLite; cancellation cannot commit
            # between this validation and the order insert.
            changed = db.execute(update(MoneyRequest).where(MoneyRequest.id == r.id,
                MoneyRequest.status == 'PENDING',
                (MoneyRequest.expires_at.is_(None) | (MoneyRequest.expires_at > now)))
                .values(status='PENDING'))
            if changed.rowcount != 1:
                raise HTTPException(409, 'Request changed. Reload before paying.')
        db.execute(update(PersonOrder).where(PersonOrder.payer_id == user.id,
            PersonOrder.status == 'READY', PersonOrder.expires_at <= now,
            ~select(PersonExecution.order_id).where(PersonExecution.order_id == PersonOrder.id).exists()).values(status='EXPIRED'))
        if r and db.scalar(select(PersonOrder.id).where(PersonOrder.request_id == r.id,
                PersonOrder.status == 'READY')):
            raise HTTPException(409, 'This request already has a prepared payment. Resume it.')
        o = PersonOrder(quote_id=q.id, payer_id=user.id, beneficiary_id=q.beneficiary_id,
            request_id=q.request_id, request_key=idempotency_key,
            created_at=now, expires_at=q.expires_at)
        db.add(o)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            old = db.scalar(select(PersonOrder).where(PersonOrder.payer_id == user.id,
                PersonOrder.request_key == idempotency_key))
            if old and old.quote_id == q.id:
                return order_view(db, old, config)
            old = db.scalar(select(PersonOrder).where(PersonOrder.quote_id == q.id))
            if old and old.request_key == idempotency_key:
                return order_view(db, old, config)
            raise HTTPException(409, 'Payment changed. Reload your prepared payment.') from None
        return order_view(db, o, config)

    def owned(db, id, user):
        o = db.scalar(select(PersonOrder).where(PersonOrder.id == id).with_for_update())
        if o is None or (o.payer_id != user.id and not (o.beneficiary_id == user.id and db.get(PersonExecution, id))):
            raise HTTPException(404, 'Payment order not found.')
        return o

    @routes.get('/orders/{id}')
    def detail(id: str, user=Depends(actor), db=Depends(database)):
        return order_view(db, owned(db, id, user), config)

    @routes.get('/orders')
    def history(user=Depends(actor), db=Depends(database)):
        rows = db.scalars(select(PersonOrder).where(PersonOrder.payer_id == user.id)
            .order_by(PersonOrder.created_at.desc(), PersonOrder.id.desc()).limit(100))
        return dict(items=[order_view(db, o, config) for o in rows], limit=100)

    @routes.post('/orders/{id}/cancel')
    def cancel(id: str, user=Depends(actor), db=Depends(database)):
        o = owned(db, id, user)
        if o.payer_id != user.id:
            raise HTTPException(403, 'Only the payer can cancel this order.')
        if db.get(PersonExecution, id):
            raise HTTPException(409, 'Payment has started. Check its status instead.')
        db.execute(update(PersonOrder).where(PersonOrder.id == o.id,
            PersonOrder.status == 'READY', PersonOrder.collection_status == 'NOT_STARTED',
            PersonOrder.delivery_status == 'NOT_STARTED').values(status='CANCELLED'))
        db.commit()
        db.refresh(o)
        return order_view(db, o, config)

    return routes
