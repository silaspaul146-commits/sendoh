"""Recipient-owned destinations and non-charging Request/Pay preflight.

An authenticated phone identity is not proof of an active mobile-money account.
Provider execution remains disabled; quotes require explicit sandbox fee policy.
"""
import time
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from .models import User, PhoneIdentity, ReceivingDestination, MoneyRequest
from .people import state, person
from .providers.mesomb import local_phone
from .fee_quotes import configured_policy
from .person_execution_state import request_execution


class DestinationConsent(BaseModel):
    model_config = ConfigDict(extra='forbid')
    method: Literal['MTN', 'ORANGE']
    expected_version: int = Field(strict=True, ge=0)
    consent: Literal['RECEIVE_ON_MY_AUTHENTICATED_PHONE']


class Preflight(BaseModel):
    model_config = ConfigDict(extra='forbid')
    recipient_id: str | None = Field(default=None, min_length=36, max_length=36)
    request_id: str | None = Field(default=None, min_length=36, max_length=36)
    amount: int | None = Field(default=None, strict=True, gt=0, le=1_000_000_000)

    @model_validator(mode='after')
    def target(self):
        if (self.recipient_id is None) == (self.request_id is None):
            raise ValueError('Choose a person or an existing request.')
        if self.request_id is not None and self.amount is not None:
            raise ValueError('The amount comes from the request.')
        if self.recipient_id is not None and self.amount is None:
            raise ValueError('Specify the amount to send.')
        return self


def current_destination(db, user_id):
    return db.scalar(select(ReceivingDestination).where(
        ReceivingDestination.user_id == user_id).order_by(
        ReceivingDestination.version.desc()).limit(1))


def identity_phone(db, user_id):
    raw = db.scalar(select(PhoneIdentity.phone).where(PhoneIdentity.user_id == user_id))
    try:
        return local_phone(raw)
    except (ValueError, TypeError):
        return None


def destination_current(db, destination):
    return destination is not None and identity_phone(db, destination.user_id) == destination.phone


def own_view(db, user_id):
    d = current_destination(db, user_id)
    return dict(version=d.version if d else 0, destination=None if d is None else dict(
        id=d.id, method=d.method, masked_phone='+237 •••••' + d.phone[-4:],
        identity_current=destination_current(db, d),
        provider_verified=False, created_at=d.created_at))


def router(database, actor, config=None):
    routes = APIRouter(prefix='/api/v1')

    @routes.get('/me/receiving-destination')
    def read(user=Depends(actor), db=Depends(database)):
        return own_view(db, user.id)

    @routes.post('/me/receiving-destination')
    def save(data: DestinationConsent, user=Depends(actor), db=Depends(database)):
        # Serialize same-user changes on PostgreSQL; unique version is the
        # fallback conflict guard on SQLite and competing transactions.
        db.scalar(select(User).where(User.id == user.id).with_for_update())
        phone = identity_phone(db, user.id)
        if not phone or not user.username or not user.display_name:
            raise HTTPException(409, 'Complete your phone identity and profile first.')
        old = current_destination(db, user.id)
        version = old.version if old else 0
        # Replaying identical consent never creates a second version.
        if old and old.phone == phone and old.method == data.method and data.expected_version in (version, version - 1):
            return own_view(db, user.id)
        if version != data.expected_version:
            raise HTTPException(409, 'Receiving details changed. Review them before saving.')
        db.add(ReceivingDestination(user_id=user.id, version=version + 1,
            phone=phone, method=data.method, created_at=int(time.time())))
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, 'Receiving details changed. Reload before saving.') from None
        return own_view(db, user.id)

    @routes.post('/person-payments/preflight')
    def preflight(data: Preflight, user=Depends(actor), db=Depends(database)):
        # Resolve requests in their correct direction: recipient owes requester.
        r = None
        if data.request_id:
            r = db.get(MoneyRequest, data.request_id)
            if r is None or r.recipient_id != user.id:
                raise HTTPException(404, 'Payable request not found.')
            if request_execution(db, r.id):
                raise HTTPException(409, 'This request has a payment in progress or completed.')
            if state(r) != 'PENDING':
                raise HTTPException(409, 'This request is no longer payable.')
            recipient_id, amount = r.requester_id, r.amount
        else:
            recipient_id, amount = data.recipient_id, data.amount
        recipient = db.get(User, recipient_id)
        if recipient is None or not recipient.username or not recipient.display_name:
            raise HTTPException(404, 'Recipient unavailable.')
        if recipient.id == user.id:
            raise HTTPException(409, 'Choose another person.')
        destination = current_destination(db, recipient.id)
        receiving_ready = destination_current(db, destination)
        blockers = []
        if not identity_phone(db, user.id) or not user.username or not user.display_name:
            blockers.append('PAYER_IDENTITY_REQUIRED')
        if not receiving_ready:
            blockers.append('RECIPIENT_RECEIVING_DETAILS_REQUIRED')
        if config is None or configured_policy() is None:
            blockers.append('FEE_QUOTE_NOT_CONFIGURED')
        blockers.append('RECIPIENT_DELIVERY_NOT_ENABLED')
        # Do not expose a recipient phone or internal destination ID to a payer.
        # This is not a quote/reservation: later execution MUST recheck expiry,
        # ownership, consent version and fee policy atomically before charging.
        return dict(purpose='REQUEST_PAYMENT' if r else 'PERSON_PAYMENT',
            request_id=r.id if r else None, recipient=person(recipient),
            recipient_amount=amount, currency='XAF',
            receiving_details_ready=receiving_ready,
            receiving_method=destination.method if receiving_ready else None,
            quote=None, can_pay=False, blockers=blockers)

    return routes
