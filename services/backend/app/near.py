"""Near2Pay: find the right person in person, without typing a phone number.

The person to be paid shows a short-lived code (QR or 6 characters). The payer
scans or types it and sees who it is, then pays through the normal Pay checkout
with its quote, explicit confirmation and verified delivery. A code only
identifies someone: it never authorizes or starts a payment.

- Codes expire after 2 minutes; showing a new code retires the previous one.
- Only a hash of each code is stored.
- Failed lookups are rate-limited per payer, so short codes cannot be guessed.
"""
import hashlib
import secrets
import time

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select, update

from .models import Collection, NearCode, NearAttempt, Participant, User

LIFETIME = 120
ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'  # no 0/O, 1/I/L
QR_PREFIX = 'sendoh:near:'
MAX_FAILURES = 10  # per payer per 10 minutes
WINDOW = 600


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def normalize(code: str) -> tuple[str, str]:
    """('token', value) for a scanned QR, ('short', value) for a typed code."""
    code = code.strip()
    if code.startswith(QR_PREFIX):
        return 'token', code[len(QR_PREFIX):]
    return 'short', code.upper().replace('-', '').replace(' ', '')


class ShowCode(BaseModel):
    model_config = ConfigDict(extra='forbid')
    amount: int | None = Field(default=None, strict=True, gt=0, le=1_000_000_000)
    # An organizer can show a code for their open collection instead of themselves.
    collection_id: str | None = Field(default=None, max_length=36)


class Lookup(BaseModel):
    model_config = ConfigDict(extra='forbid')
    code: str = Field(min_length=4, max_length=200)


def router(database, actor):
    routes = APIRouter(prefix='/api/v1/near')

    def throttle(db, user, failed: bool):
        now = int(time.time())
        row = db.get(NearAttempt, user.id)
        if row is None:
            row = NearAttempt(user_id=user.id, window_start=now, failures=0)
            db.add(row)
        elif row.window_start <= now - WINDOW:
            row.window_start, row.failures = now, 0
        if failed:
            row.failures += 1
        return row.failures >= MAX_FAILURES

    @routes.post('/codes', status_code=201)
    def show(data: ShowCode, user=Depends(actor), db=Depends(database)):
        if not user.username or not user.display_name:
            raise HTTPException(409, 'Complete your profile first.')
        now = int(time.time())
        collection = None
        if data.collection_id is not None:
            collection = db.scalar(select(Collection).where(Collection.id == data.collection_id,
                                                            Collection.organizer_id == user.id))
            if collection is None:
                raise HTTPException(404, 'Collection not found.')
            if collection.status != 'ACTIVE':
                raise HTTPException(409, 'Only open collections can take contributions.')
        db.scalar(select(User).where(User.id == user.id).with_for_update())
        # One live code per person: a new code retires the previous one.
        db.execute(update(NearCode).where(NearCode.user_id == user.id,
                                          NearCode.expires_at > now).values(expires_at=now))
        token = secrets.token_urlsafe(24)
        for _ in range(5):
            short = ''.join(secrets.choice(ALPHABET) for _ in range(6))
            if not db.scalar(select(NearCode.id).where(NearCode.short_hash == digest(short),
                                                       NearCode.expires_at > now)):
                break
        db.add(NearCode(user_id=user.id, token_hash=digest(token), short_hash=digest(short),
                        amount=data.amount, created_at=now, expires_at=now + LIFETIME,
                        collection_id=collection.id if collection else None))
        db.commit()
        return dict(qr=QR_PREFIX + token, short_code=f'{short[:3]}-{short[3:]}',
                    purpose='COLLECTION' if collection else 'PERSON',
                    collection_id=collection.id if collection else None,
                    amount=data.amount, expires_at=now + LIFETIME, lifetime=LIFETIME, created_at=now)

    @routes.post('/resolve')
    def resolve(data: Lookup, user=Depends(actor), db=Depends(database)):
        now = int(time.time())
        db.scalar(select(User).where(User.id == user.id).with_for_update())
        row = db.get(NearAttempt, user.id)
        if row and row.window_start > now - WINDOW and row.failures >= MAX_FAILURES:
            raise HTTPException(429, 'Too many codes tried. Wait a few minutes, then try again.')
        kind, value = normalize(data.code)
        column = NearCode.token_hash if kind == 'token' else NearCode.short_hash
        code = db.scalar(select(NearCode).where(column == digest(value), NearCode.expires_at > now))
        if code is None:
            throttle(db, user, failed=True)
            db.commit()
            raise HTTPException(404, 'This code has expired or is not valid. Ask them to show a new one.')
        if code.user_id == user.id:
            db.commit()
            raise HTTPException(409, 'This is your own code.')
        throttle(db, user, failed=False)
        db.commit()
        target = db.get(User, code.user_id)
        person = dict(id=target.id, name=target.display_name, identity='@' + target.username)
        if code.collection_id:
            c = db.get(Collection, code.collection_id)
            if c is None or c.status != 'ACTIVE':
                raise HTTPException(409, 'This collection is no longer taking contributions.')
            member = db.scalar(select(Participant).where(Participant.collection_id == c.id,
                                                         Participant.user_id == user.id))
            # Contributing credits the payer's own share; joining is a separate, explicit step.
            return dict(purpose='COLLECTION', organizer=person, amount=code.amount,
                        expires_at=code.expires_at,
                        collection=dict(id=c.id, name=c.name, token=c.public_token,
                                        expected_amount=c.expected_amount),
                        membership=member.invitation_state if member else 'NOT_JOINED')
        # Identity and amount only; the payer still confirms and authorizes in checkout.
        return dict(purpose='PERSON', person=person, amount=code.amount, expires_at=code.expires_at)

    return routes
