"""Mobile Money numbers: how a person pays and gets paid. Not who they are.

A person is their name and @username. The phone they sign in with is only a
key. They may keep up to three Mobile Money numbers (MTN MoMo or Orange Money),
each verified by an SMS code sent to that number. A parent's number works too:
the parent reading out the code is their consent. The sign-in number is
verified by signing in, so adding it needs no second code.

One verified number is the default to pay with, one the default to receive on.
Choosing a receive default records a new receiving-destination version, so
payouts and transfers already in flight keep the destination they were quoted.

The sign-in number can be changed: a code goes to the new number first.
"""
import hashlib
import secrets
import time

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError

from .models import MoneyNumber, NumberChallenge, PhoneIdentity, ReceivingDestination, User
from .otp import deliver_otp, test_code
from .providers.mesomb import local_phone

LIMIT = 3
CODE_TTL = 300
RESEND_AFTER = 60


def network(phone: str) -> str | None:
    """MTN or Orange from a Cameroon mobile prefix; None when unknown."""
    p = local_phone(phone)
    two, three = p[:2], int(p[:3])
    if two == '67' or 650 <= three <= 654 or 680 <= three <= 684:
        return 'MTN'
    if two == '69' or 655 <= three <= 659 or 685 <= three <= 689:
        return 'ORANGE'
    return None


def masked(phone: str) -> str:
    return phone[:3] + ' •• •• ' + phone[-2:]


def identity(db, user_id) -> str | None:
    raw = db.scalar(select(PhoneIdentity.phone).where(PhoneIdentity.user_id == user_id))
    try:
        return local_phone(raw)
    except (ValueError, TypeError):
        return None


def active(db, user_id):
    return list(db.scalars(select(MoneyNumber).where(
        MoneyNumber.user_id == user_id, MoneyNumber.removed_at.is_(None)).order_by(MoneyNumber.created_at)))


def verified_phones(db, user_id) -> set[str]:
    return {n.phone for n in active(db, user_id) if n.verified_at}


def can_pay_with(db, user_id, phone) -> bool:
    """The sign-in number, or any verified Mobile Money number of this person."""
    return phone is not None and (phone == identity(db, user_id) or phone in verified_phones(db, user_id))


def payer(db, user_id, number_id=None):
    """(phone, method) to charge: a chosen verified number, else the pay default, else None."""
    numbers = [n for n in active(db, user_id) if n.verified_at]
    if number_id:
        chosen = next((n for n in numbers if n.id == number_id), None)
        if chosen is None:
            raise HTTPException(409, 'Choose one of your verified Mobile Money numbers.')
        return chosen.phone, chosen.method
    default = next((n for n in numbers if n.pay_default), None)
    return (default.phone, default.method) if default else (None, None)


def view(n: MoneyNumber, signin: str | None):
    # Only ever shown to the number's owner.
    return dict(id=n.id, method=n.method, phone=n.phone, masked=masked(n.phone), last_digits=n.phone[-2:],
                verified=n.verified_at is not None,
                # A number waiting for its code is never shown as a default yet.
                pay_default=bool(n.verified_at and n.pay_default),
                receive_default=bool(n.verified_at and n.receive_default),
                is_sign_in_number=n.phone == signin)


def listing(db, user_id):
    signin = identity(db, user_id)
    return dict(numbers=[view(n, signin) for n in active(db, user_id)], limit=LIMIT,
                sign_in_masked=('+237 ' + masked(signin)) if signin else None,
                sign_in_network=network(signin) if signin else None)


def _digest(challenge_id, code):
    return hashlib.sha256((challenge_id + code).encode()).hexdigest()


class NumberInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    phone: str | None = Field(default=None, min_length=9, max_length=13)
    # Add the number you sign in with; it is already verified.
    sign_in_number: bool = False
    method: str | None = Field(default=None, pattern='^(MTN|ORANGE)$')
    pay_default: bool = False
    receive_default: bool = False


class CodeInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    challenge_id: str = Field(min_length=36, max_length=36)
    code: str = Field(pattern=r'^[0-9]{6}$')


class DefaultsInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    pay_default: bool | None = None
    receive_default: bool | None = None


class PhoneInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    phone: str = Field(min_length=9, max_length=13)


def router(database, actor, settings):
    routes = APIRouter(prefix='/api/v1/me')

    def send(db, user, purpose, phone, number_id=None):
        now = int(time.time())
        recent = db.scalar(select(NumberChallenge).where(
            NumberChallenge.user_id == user.id, NumberChallenge.phone == phone,
            NumberChallenge.sent_at > now - RESEND_AFTER))
        if recent:
            raise HTTPException(429, 'Wait 60 seconds before requesting another code.')
        challenge_id, code = str(secrets.token_hex(16)), f'{secrets.randbelow(1000000):06d}'
        challenge_id = f'{challenge_id[:8]}-{challenge_id[8:12]}-{challenge_id[12:16]}-{challenge_id[16:20]}-{challenge_id[20:32]}'
        db.add(NumberChallenge(id=challenge_id, user_id=user.id, purpose=purpose, phone=phone,
                               number_id=number_id, code_hash=_digest(challenge_id, code),
                               sent_at=now, expires_at=now + CODE_TTL, attempts=0))
        db.flush()
        try:
            delivery = deliver_otp(settings, '+237' + phone, challenge_id, code)
        except Exception:
            db.rollback()
            raise HTTPException(503, 'The verification message could not be sent. Please try again.') from None
        db.commit()
        return dict(challenge_id=challenge_id, expires_in=CODE_TTL, resend_after=RESEND_AFTER,
                    delivery=delivery, **({'test_code': test_code(settings, code)} if test_code(settings, code) else {}))

    def check(db, user, purpose, data: CodeInput):
        now = int(time.time())
        claimed = db.execute(update(NumberChallenge).where(
            NumberChallenge.id == data.challenge_id, NumberChallenge.user_id == user.id,
            NumberChallenge.purpose == purpose, NumberChallenge.expires_at > now,
            NumberChallenge.attempts < 5).values(attempts=NumberChallenge.attempts + 1))
        if claimed.rowcount != 1:
            db.rollback()
            raise HTTPException(400, 'Code expired, already used, or too many attempts. Request another code.')
        c = db.get(NumberChallenge, data.challenge_id)
        if not secrets.compare_digest(c.code_hash, _digest(data.challenge_id, data.code)):
            db.commit()
            raise HTTPException(400, 'Incorrect code.')
        c.expires_at = 0
        return c

    def owned(db, user, number_id):
        n = db.get(MoneyNumber, number_id)
        if n is None or n.user_id != user.id or n.removed_at is not None:
            raise HTTPException(404, 'Mobile Money number not found.')
        return n

    def make_default(db, user, n, pay=None, receive=None):
        if (pay or receive) and not n.verified_at:
            raise HTTPException(409, 'Verify this number first.')
        others = [o for o in active(db, user.id) if o.id != n.id]
        if pay is not None:
            n.pay_default = pay
            if pay:
                for o in others:
                    o.pay_default = False
        if receive is not None:
            n.receive_default = receive
            if receive:
                for o in others:
                    o.receive_default = False
                record_destination(db, user.id, n)

    def record_destination(db, user_id, n):
        old = db.scalar(select(ReceivingDestination).where(ReceivingDestination.user_id == user_id)
                        .order_by(ReceivingDestination.version.desc()).limit(1))
        if old and old.phone == n.phone and old.method == n.method:
            return
        db.add(ReceivingDestination(user_id=user_id, version=(old.version if old else 0) + 1,
                                    phone=n.phone, method=n.method, created_at=int(time.time())))

    @routes.get('/money-numbers')
    def read(user=Depends(actor), db=Depends(database)):
        return listing(db, user.id)

    @routes.post('/money-numbers')
    def add(data: NumberInput, user=Depends(actor), db=Depends(database)):
        db.scalar(select(User).where(User.id == user.id).with_for_update())
        try:
            phone = identity(db, user.id) if data.sign_in_number else local_phone(data.phone)
            if phone is None:
                raise ValueError
        except (ValueError, TypeError):
            raise HTTPException(422, 'Enter a valid Mobile Money number.') from None
        method = data.method or network(phone)
        if method is None:
            raise HTTPException(422, 'Choose MTN MoMo or Orange Money for this number.')
        numbers = active(db, user.id)
        existing = next((n for n in numbers if n.phone == phone), None)
        if existing is None and len(numbers) >= LIMIT:
            raise HTTPException(409, 'You can keep up to 3 Mobile Money numbers. Remove one first.')
        n = existing or MoneyNumber(user_id=user.id, phone=phone, method=method, created_at=int(time.time()))
        n.method = method
        if existing is None:
            db.add(n)
        db.flush()
        # The sign-in number was verified by signing in.
        if phone == identity(db, user.id) and n.verified_at is None:
            n.verified_at = int(time.time())
        challenge = None
        if n.verified_at:
            make_default(db, user, n, data.pay_default or None, data.receive_default or None)
            first = not any(o.verified_at for o in numbers if o.id != n.id)
            if first:  # The first verified number becomes both defaults.
                make_default(db, user, n, True, True)
        else:
            # Defaults wait for verification; remember what was asked.
            n.pay_default, n.receive_default = data.pay_default, data.receive_default
        try:
            db.flush()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, 'This number was just added. Refresh and try again.') from None
        if not n.verified_at:
            challenge = send(db, user, 'MONEY_NUMBER', phone, n.id)
        else:
            db.commit()
        return dict(listing(db, user.id), number=view(n, identity(db, user.id)), challenge=challenge)

    @routes.post('/money-numbers/{number_id}/code')
    def resend(number_id: str, user=Depends(actor), db=Depends(database)):
        n = owned(db, user, number_id)
        if n.verified_at:
            raise HTTPException(409, 'This number is already verified.')
        return send(db, user, 'MONEY_NUMBER', n.phone, n.id)

    @routes.post('/money-numbers/{number_id}/verify')
    def verify(number_id: str, data: CodeInput, user=Depends(actor), db=Depends(database)):
        n = owned(db, user, number_id)
        c = check(db, user, 'MONEY_NUMBER', data)
        if c.number_id != n.id:
            db.rollback()
            raise HTTPException(400, 'Code expired, already used, or too many attempts. Request another code.')
        if n.verified_at is None:
            n.verified_at = int(time.time())
            asked_pay, asked_receive = n.pay_default, n.receive_default
            n.pay_default = n.receive_default = False
            first = not any(o.verified_at for o in active(db, user.id) if o.id != n.id)
            make_default(db, user, n, asked_pay or first or None, asked_receive or first or None)
        db.commit()
        return dict(listing(db, user.id), number=view(n, identity(db, user.id)))

    @routes.post('/money-numbers/{number_id}/defaults')
    def defaults(number_id: str, data: DefaultsInput, user=Depends(actor), db=Depends(database)):
        n = owned(db, user, number_id)
        make_default(db, user, n, data.pay_default, data.receive_default)
        db.commit()
        return listing(db, user.id)

    @routes.post('/money-numbers/{number_id}/remove')
    def remove(number_id: str, user=Depends(actor), db=Depends(database)):
        n = owned(db, user, number_id)
        n.removed_at = int(time.time())
        n.pay_default = n.receive_default = False
        db.commit()
        return listing(db, user.id)

    @routes.post('/sign-in-number/code')
    def change_code(data: PhoneInput, user=Depends(actor), db=Depends(database)):
        try:
            phone = local_phone(data.phone)
        except ValueError:
            raise HTTPException(422, 'Enter a valid Cameroon phone number.') from None
        if phone == identity(db, user.id):
            raise HTTPException(409, 'This is already your sign-in number.')
        if db.get(PhoneIdentity, '+237' + phone):
            raise HTTPException(409, 'This number already signs in to another Sendoh account.')
        return send(db, user, 'SIGN_IN', phone)

    @routes.post('/sign-in-number/verify')
    def change_verify(data: CodeInput, user=Depends(actor), db=Depends(database)):
        c = check(db, user, 'SIGN_IN', data)
        new = '+237' + c.phone
        if db.get(PhoneIdentity, new):
            db.rollback()
            raise HTTPException(409, 'This number already signs in to another Sendoh account.')
        db.execute(PhoneIdentity.__table__.delete().where(PhoneIdentity.user_id == user.id))
        db.add(PhoneIdentity(phone=new, user_id=user.id))
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, 'This number already signs in to another Sendoh account.') from None
        return listing(db, user.id)

    return routes
