"""Local development verification. SMS delivery is deliberately not simulated."""
import hashlib
import os
import secrets
import time
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from .models import User, PhoneIdentity, OtpChallenge, AuthSession, uid


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def otp_directory():
    return Path(os.getenv('SENDOH_DEV_OTP_DIR', '.dev-otp'))


class PhoneInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    phone: str = Field(pattern=r'^\+237[26][0-9]{8}$')


class VerifyInput(PhoneInput):
    challenge_id: str = Field(min_length=36, max_length=36)
    code: str = Field(pattern=r'^[0-9]{6}$')


class ProfileInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    display_name: str = Field(min_length=1, max_length=120)


def profile(user):
    return {'id': user.id, 'display_name': user.display_name,
            'profile_complete': bool(user.display_name), 'auth_mode': 'development'}


def router(database, actor, bearer):
    routes = APIRouter(prefix='/api/v1')

    @routes.post('/auth/code')
    def send_code(data: PhoneInput, db=Depends(database)):
        now = int(time.time())
        challenge_id, code = uid(), f'{secrets.randbelow(1000000):06d}'
        values = dict(challenge_id=challenge_id, code_hash=digest(challenge_id + code),
                      sent_at=now, expires_at=now + 300, attempts=0)
        existing = db.get(OtpChallenge, data.phone)
        if existing:
            result = db.execute(update(OtpChallenge).where(
                OtpChallenge.phone == data.phone, OtpChallenge.sent_at <= now - 60).values(**values))
            if result.rowcount != 1:
                db.rollback()
                raise HTTPException(429, 'Wait 60 seconds before requesting another code.')
        else:
            db.add(OtpChallenge(phone=data.phone, **values))
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(429, 'Wait 60 seconds before requesting another code.')
        directory = otp_directory()
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        path = directory / challenge_id
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream:
            stream.write(code)
        return {'challenge_id': challenge_id, 'expires_in': 300, 'resend_after': 60,
                'delivery': 'local-development', 'message': 'No SMS sent. Retrieve the code on the API computer.'}

    @routes.post('/auth/verify')
    def verify(data: VerifyInput, db=Depends(database)):
        now = int(time.time())
        # Atomic attempt claim also serializes concurrent verification/resend for this phone.
        result = db.execute(update(OtpChallenge).where(
            OtpChallenge.phone == data.phone, OtpChallenge.challenge_id == data.challenge_id,
            OtpChallenge.expires_at > now, OtpChallenge.attempts < 5
        ).values(attempts=OtpChallenge.attempts + 1))
        if result.rowcount != 1:
            db.rollback()
            raise HTTPException(400, 'Code expired, already used, or too many attempts. Request another code.')
        challenge = db.get(OtpChallenge, data.phone)
        if not secrets.compare_digest(challenge.code_hash, digest(data.challenge_id + data.code)):
            db.commit()
            raise HTTPException(400, 'Incorrect code.')
        challenge.expires_at = 0
        identity = db.get(PhoneIdentity, data.phone)
        if identity:
            user = db.get(User, identity.user_id)
        else:
            user = User(display_name='', token_hash=digest(secrets.token_urlsafe(48)))
            db.add(user)
            db.flush()
            db.add(PhoneIdentity(phone=data.phone, user_id=user.id))
        token = secrets.token_urlsafe(48)
        db.add(AuthSession(token_hash=digest(token), user_id=user.id, expires_at=now + 43200))
        db.commit()
        (otp_directory() / data.challenge_id).unlink(missing_ok=True)
        return {'access_token': token, 'expires_in': 43200, 'user': profile(user)}

    @routes.post('/me/profile')
    def save_profile(data: ProfileInput, user=Depends(actor), db=Depends(database)):
        user.display_name = data.display_name
        db.commit()
        return profile(user)

    @routes.post('/auth/logout')
    def logout(user=Depends(actor), credentials=Depends(bearer), db=Depends(database)):
        db.execute(update(AuthSession).where(AuthSession.token_hash == digest(credentials.credentials)).values(expires_at=0))
        db.commit()
        return {'signed_out': True}

    return routes
