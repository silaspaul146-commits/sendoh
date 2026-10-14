"""Persisted staging payments. No provider calls and no real money ledger writes."""
import hashlib
import json
import os
import time
from typing import Literal
from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import select, func, update
from sqlalchemy.exc import IntegrityError
from .models import TestPayment, Collection, Participant, PhoneIdentity, Activity, User
from .notifications import emit


def enabled(settings):
    return settings.environment in ('development', 'staging') and os.getenv('SENDOH_TEST_PAYMENTS') == '1'


def total(db, collection_id, participant_id=None):
    query = select(func.coalesce(func.sum(TestPayment.amount), 0)).where(
        TestPayment.collection_id == collection_id, TestPayment.status == 'SUCCEEDED')
    if participant_id is not None:
        query = query.where(TestPayment.participant_id == participant_id)
    return int(db.scalar(query))


def view(p):
    return dict(id=p.id, reference='TEST-' + p.id.upper(), mode='TEST', currency='XAF',
                collection_id=p.collection_id, collection_name=p.collection_name,
                participant_id=p.participant_id, payer_name=p.payer_name,
                amount=p.amount, fee_amount=0, total_amount=p.amount, method=p.method,
                note=p.note, status=p.status, created_at=p.created_at,
                completed_at=p.completed_at, receipt_available=p.status == 'SUCCEEDED',
                notice='TEST ONLY — no money moved. Not proof of payment.')


class Intent(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    collection_id: str | None = Field(default=None, min_length=36, max_length=36)
    collection_token: str | None = Field(default=None, min_length=1, max_length=80)
    amount: int = Field(strict=True, gt=0, le=1_000_000_000_000)
    method: Literal['MTN', 'ORANGE']
    note: str = Field(default='', max_length=200)

    @model_validator(mode='after')
    def target(self):
        if (self.collection_id is None) == (self.collection_token is None):
            raise ValueError('Supply one collection identifier.')
        return self


class Outcome(BaseModel):
    model_config = ConfigDict(extra='forbid')
    status: Literal['SUCCEEDED', 'FAILED', 'CANCELLED']


def router(database, actor, settings):
    routes = APIRouter(prefix='/api/v1')

    def require_test():
        if not enabled(settings):
            raise HTTPException(403, 'Test payments are disabled on this server.')

    def owned_payment(db, payment_id, user, payer_only=False):
        p = db.get(TestPayment, payment_id)
        c = db.get(Collection, p.collection_id) if p else None
        if not p or (p.payer_id != user.id and (payer_only or c.organizer_id != user.id)):
            raise HTTPException(404, 'Payment not found.')
        return p

    @routes.post('/test-payments', status_code=201)
    def create(data: Intent, idempotency_key: str = Header(min_length=8, max_length=120),
               user=Depends(actor), db=Depends(database)):
        require_test()
        # Serialize per-account creation on PostgreSQL, including retry/rate checks.
        db.scalar(select(User).where(User.id == user.id).with_for_update())
        fingerprint = hashlib.sha256(json.dumps(data.model_dump(), sort_keys=True).encode()).hexdigest()
        existing = db.scalar(select(TestPayment).where(TestPayment.payer_id == user.id,
                                                       TestPayment.request_key == idempotency_key))
        if existing:
            if existing.fingerprint != fingerprint:
                raise HTTPException(409, 'This request key was used for different payment details.')
            return view(existing)
        recent = db.scalar(select(func.count()).select_from(TestPayment).where(
            TestPayment.payer_id == user.id, TestPayment.created_at > int(time.time()) - 60))
        if recent >= 20:
            raise HTTPException(429, 'Please wait a minute before starting more test payments.')
        if not user.display_name or not db.scalar(select(PhoneIdentity.phone).where(PhoneIdentity.user_id == user.id)):
            raise HTTPException(403, 'Verify your phone and complete your name before contributing.')
        target = Collection.id == data.collection_id if data.collection_id else Collection.public_token == data.collection_token
        c = db.scalar(select(Collection).where(target).with_for_update())
        if not c or c.status != 'ACTIVE':
            raise HTTPException(404, 'Active collection not found.')
        p = db.scalar(select(Participant).where(Participant.collection_id == c.id, Participant.user_id == user.id))
        if not p and c.organizer_id == user.id:
            p = Participant(collection_id=c.id, user_id=user.id, name=user.display_name,
                            expected_amount=c.expected_amount, invitation_state='ACCEPTED')
            db.add(p)
            db.flush()
        if not p or p.invitation_state != 'ACCEPTED':
            raise HTTPException(403, 'Join this collection as yourself before contributing.')
        if c.mode == 'MINIMUM_TOTAL':
            minimum = p.expected_amount or c.expected_amount or 0
            if total(db, c.id, p.id) + data.amount < minimum:
                raise HTTPException(422, f'Your successful test contributions must total at least {minimum} FCFA.')
        payment = TestPayment(collection_id=c.id, participant_id=p.id, payer_id=user.id,
            payer_name=user.display_name, collection_name=c.name, request_key=idempotency_key,
            fingerprint=fingerprint, amount=data.amount, method=data.method, note=data.note,
            status='PENDING', created_at=int(time.time()))
        db.add(payment)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            existing = db.scalar(select(TestPayment).where(TestPayment.payer_id == user.id,
                                                           TestPayment.request_key == idempotency_key))
            if not existing:
                raise
            if existing.fingerprint != fingerprint:
                raise HTTPException(409, 'This request key was used for different payment details.')
            return view(existing)
        return view(payment)

    @routes.get('/test-payments/{payment_id}')
    def detail(payment_id: str, user=Depends(actor), db=Depends(database)):
        return view(owned_payment(db, payment_id, user))

    @routes.post('/test-payments/{payment_id}/simulate')
    def settle(payment_id: str, data: Outcome, user=Depends(actor), db=Depends(database)):
        require_test()
        p = owned_payment(db, payment_id, user, payer_only=True)
        if p.status != 'PENDING':
            if p.status != data.status:
                raise HTTPException(409, 'This test payment already has a final result. Start a new attempt.')
            return view(p)
        changed = db.execute(update(TestPayment).where(TestPayment.id == p.id,
            TestPayment.status == 'PENDING').values(status=data.status, completed_at=int(time.time())))
        if changed.rowcount != 1:
            db.rollback()
            db.expire_all()
            p = owned_payment(db, payment_id, user, payer_only=True)
            if p.status != data.status:
                raise HTTPException(409, 'This test payment already has a final result.')
            return view(p)
        db.flush()
        db.refresh(p)
        c = db.get(Collection, p.collection_id)
        member = db.get(Participant, p.participant_id)
        if p.status == 'SUCCEEDED':
            db.add(Activity(organizer_id=c.organizer_id, collection_id=c.id,
                message=f'TEST: {p.payer_name[:100]} contributed {p.amount} FCFA (no money moved)'))
            emit(db, c.organizer_id, member, 'TEST_PAYMENT', event_id=p.id)
            if c.organizer_id != p.payer_id:
                emit(db, p.payer_id, member, 'TEST_PAYMENT', event_id=p.id)
        db.commit()
        return view(p)

    @routes.get('/me/test-payments')
    def mine(collection_id: str | None = None, collection_token: str | None = None,
             before: str | None = None, user=Depends(actor), db=Depends(database)):
        query = select(TestPayment).where(TestPayment.payer_id == user.id)
        if collection_token:
            c = db.scalar(select(Collection).where(Collection.public_token == collection_token))
            if not c:
                raise HTTPException(404, 'Collection not found.')
            collection_id = c.id
        if collection_id:
            query = query.where(TestPayment.collection_id == collection_id)
        return page(db, query, before)

    @routes.get('/collections/{collection_id}/test-payments')
    def organized(collection_id: str, before: str | None = None,
                  user=Depends(actor), db=Depends(database)):
        c = db.get(Collection, collection_id)
        if not c or c.organizer_id != user.id:
            raise HTTPException(404, 'Collection not found.')
        result = page(db, select(TestPayment).where(TestPayment.collection_id == collection_id), before)
        result['test_collected_amount'] = total(db, collection_id)
        return result

    return routes


def page(db, query, before):
    from sqlalchemy import or_, and_
    if before:
        cursor = db.scalar(query.where(TestPayment.id == before))
        if not cursor:
            raise HTTPException(404, 'Payment cursor not found.')
        query = query.where(or_(TestPayment.created_at < cursor.created_at,
            and_(TestPayment.created_at == cursor.created_at, TestPayment.id < cursor.id)))
    rows = db.scalars(query.order_by(TestPayment.created_at.desc(), TestPayment.id.desc()).limit(51)).all()
    return dict(items=[view(p) for p in rows[:50]], next_cursor=rows[49].id if len(rows) > 50 else None)
