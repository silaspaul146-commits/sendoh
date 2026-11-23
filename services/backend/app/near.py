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

from .models import NearCode, NearAttempt, User

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
                        amount=data.amount, created_at=now, expires_at=now + LIFETIME))
        db.commit()
        return dict(qr=QR_PREFIX + token, short_code=f'{short[:3]}-{short[3:]}',
                    amount=data.amount, expires_at=now + LIFETIME, lifetime=LIFETIME)

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
        # Identity and amount only; the payer still confirms and authorizes in checkout.
        return dict(person=dict(id=target.id, name=target.display_name, identity='@' + target.username),
                    amount=code.amount, expires_at=code.expires_at)

    return routes
