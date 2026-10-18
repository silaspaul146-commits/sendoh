"""Exact identity lookup and money requests. No payment execution endpoints."""
import hashlib
import json
import time
from typing import Literal
from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select, or_, update, func
from sqlalchemy.exc import IntegrityError
from .models import User, MoneyRequest, Notification, PushDevice, PushDelivery

class Lookup(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    identity: str = Field(min_length=3, max_length=80)
    from_qr: bool = False

class CreateRequest(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    recipient_id: str = Field(min_length=36, max_length=36)
    amount: int = Field(strict=True, gt=0, le=1_000_000_000)
    reason: str = Field(min_length=1, max_length=140)
    expires_at: int | None = Field(default=None, strict=True)

class Respond(BaseModel):
    model_config = ConfigDict(extra='forbid')
    action: Literal['DECLINE', 'CANCEL']

def person(user):
    return dict(id=user.id, name=user.display_name, identity='@' + user.username)

def state(r):
    return 'EXPIRED' if r.status == 'PENDING' and r.expires_at is not None and r.expires_at <= int(time.time()) else r.status

def view(db, r, actor_id):
    return dict(id=r.id, amount=r.amount, currency='XAF', reason=r.reason,
        requester=person(db.get(User, r.requester_id)), recipient=person(db.get(User, r.recipient_id)),
        direction='SENT' if actor_id == r.requester_id else 'RECEIVED',
        status=state(r), expires_at=r.expires_at, created_at=r.created_at,
        payment_available=False)

def notify(db, r, recipient, kind):
    timestamp = int(time.time())
    n = Notification(user_id=recipient, request_id=r.id, kind=kind,
        event_key=f'{r.id}:{kind}:{recipient}', created_at=timestamp)
    db.add(n); db.flush()
    for device in db.scalars(select(PushDevice).where(PushDevice.user_id == recipient,
            PushDevice.active == 1, PushDevice.expires_at > timestamp)):
        db.add(PushDelivery(notification_id=n.id, device_id=device.id,
            token_hash=device.token_hash, family_id=device.family_id, due_at=timestamp))

def router(database, actor):
    routes = APIRouter(prefix='/api/v1')

    @routes.post('/people/resolve')
    def resolve(data: Lookup, user=Depends(actor), db=Depends(database)):
        # Exact public usernames only: never expose a phone-number directory.
        if data.from_qr:
            raise HTTPException(409, 'QR identity resolution is not enabled yet. Use a Sendoh username.')
        name = data.identity.removeprefix('@').lower()
        target = db.scalar(select(User).where(User.username == name))
        if not target or not target.display_name:
            raise HTTPException(404, 'Sendoh person not found. Use their exact username.')
        if target.id == user.id:
            raise HTTPException(409, 'Choose another person.')
        return person(target)

    @routes.post('/money-requests', status_code=201)
    def create(data: CreateRequest, idempotency_key: str = Header(min_length=8, max_length=120),
               user=Depends(actor), db=Depends(database)):
        if not user.username or not user.display_name:
            raise HTTPException(409, 'Complete your profile first.')
        db.scalar(select(User).where(User.id == user.id).with_for_update())
        digest = hashlib.sha256(json.dumps(data.model_dump(), sort_keys=True).encode()).hexdigest()
        existing = db.scalar(select(MoneyRequest).where(MoneyRequest.requester_id == user.id, MoneyRequest.request_key == idempotency_key))
        if existing:
            if existing.fingerprint != digest:
                raise HTTPException(409, 'This request key was used for different details.')
            return view(db, existing, user.id)
        timestamp = int(time.time())
        if data.expires_at is not None and not timestamp < data.expires_at <= timestamp + 366 * 86400:
            raise HTTPException(422, 'Choose a future expiry within one year.')
        recipient = db.get(User, data.recipient_id)
        if not recipient or not recipient.username or not recipient.display_name or recipient.id == user.id:
            raise HTTPException(404, 'Recipient unavailable.')
        recent = db.scalar(select(func.count()).select_from(MoneyRequest).where(
            MoneyRequest.requester_id == user.id, MoneyRequest.created_at > timestamp - 3600))
        if recent >= 20:
            raise HTTPException(429, 'Request limit reached. Try later.')
        r = MoneyRequest(requester_id=user.id, recipient_id=recipient.id, amount=data.amount,
            reason=data.reason, expires_at=data.expires_at, status='PENDING',
            request_key=idempotency_key, fingerprint=digest, created_at=timestamp)
        try:
            db.add(r); db.flush(); notify(db, r, recipient.id, 'REQUEST_RECEIVED'); db.commit()
        except IntegrityError:
            db.rollback()
            existing = db.scalar(select(MoneyRequest).where(MoneyRequest.requester_id == user.id, MoneyRequest.request_key == idempotency_key))
            if existing and existing.fingerprint == digest:
                return view(db, existing, user.id)
            raise HTTPException(409, 'Request changed. Refresh before retrying.')
        return view(db, r, user.id)

    @routes.get('/money-requests')
    def inbox(user=Depends(actor), db=Depends(database)):
        rows = db.scalars(select(MoneyRequest).where(or_(MoneyRequest.requester_id == user.id,
            MoneyRequest.recipient_id == user.id)).order_by(MoneyRequest.created_at.desc(), MoneyRequest.id.desc()).limit(100)).all()
        return dict(items=[view(db, r, user.id) for r in rows], limit=100)

    def owned(db, id, user):
        r = db.get(MoneyRequest, id)
        if not r or user.id not in (r.requester_id, r.recipient_id):
            raise HTTPException(404, 'Request not found.')
        return r

    @routes.get('/money-requests/{id}')
    def detail(id: str, user=Depends(actor), db=Depends(database)):
        return view(db, owned(db, id, user), user.id)

    @routes.post('/money-requests/{id}/respond')
    def respond(id: str, data: Respond, user=Depends(actor), db=Depends(database)):
        r = owned(db, id, user)
        decline = data.action == 'DECLINE'
        if user.id != (r.recipient_id if decline else r.requester_id):
            raise HTTPException(403, 'This action is not yours.')
        desired = 'DECLINED' if decline else 'CANCELLED'
        if r.status == desired:
            return view(db, r, user.id)
        if state(r) != 'PENDING':
            raise HTTPException(409, 'This request is no longer pending.')
        changed = db.execute(update(MoneyRequest).where(MoneyRequest.id == id, MoneyRequest.status == 'PENDING',
            or_(MoneyRequest.expires_at.is_(None), MoneyRequest.expires_at > int(time.time())))
            .values(status=desired))
        if changed.rowcount != 1:
            db.rollback(); raise HTTPException(409, 'Request changed. Refresh its status.')
        notify(db, r, r.requester_id if decline else r.recipient_id,
            'REQUEST_DECLINED' if decline else 'REQUEST_CANCELLED')
        db.commit(); db.refresh(r)
        return view(db, r, user.id)
    return routes
