"""Local development verification. SMS delivery is deliberately not simulated."""
import hashlib
import secrets
import time
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from .models import User, PhoneIdentity, OtpChallenge, AuthSession, RefreshSession, PushDevice, uid
from .avatars import sanitize_avatar
from .config import Settings
from .otp import deliver_otp, otp_directory


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


class PhoneInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    phone: str = Field(pattern=r'^\+237[26][0-9]{8}$')


class VerifyInput(PhoneInput):
    challenge_id: str = Field(min_length=36, max_length=36)
    code: str = Field(pattern=r'^[0-9]{6}$')


class ProfileInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    display_name: str = Field(min_length=1, max_length=120)
    username: str | None = Field(default=None, min_length=3, max_length=24, pattern=r'^[a-z][a-z0-9_]{2,23}$')
    avatar: str | None = Field(default=None, max_length=270000)

    @field_validator('username', mode='before')
    @classmethod
    def normalize_username(cls, value):
        return value.strip().lower() if isinstance(value, str) else value

class RefreshInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    refresh_token: str = Field(min_length=40, max_length=128)

def issue_session(db, user, family_id=None, expires_at=None):
    now = int(time.time())
    family_id = family_id or uid()
    expiry = expires_at or now + 30 * 86400
    token, refresh = secrets.token_urlsafe(48), secrets.token_urlsafe(48)
    db.add(AuthSession(token_hash=digest(token), user_id=user.id,
                       expires_at=min(now + 43200, expiry), family_id=family_id))
    db.add(RefreshSession(token_hash=digest(refresh), user_id=user.id,
                          family_id=family_id, expires_at=expiry))
    return {'access_token': token, 'refresh_token': refresh,
            'expires_in': min(43200, expiry - now)}

def revoke_family(db, family_id):
    db.execute(update(PushDevice).where(PushDevice.family_id == family_id).values(active=0))
    db.execute(update(AuthSession).where(AuthSession.family_id == family_id).values(expires_at=0))
    db.execute(update(RefreshSession).where(RefreshSession.family_id == family_id).values(expires_at=0))


def profile(user, environment='development'):
    return {'id': user.id, 'display_name': user.display_name,
            'username': user.username, 'avatar': user.avatar,
            'profile_complete': bool(user.display_name and user.username), 'auth_mode': environment}


def router(database, actor, bearer, settings: Settings):
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
        try:
            delivery = deliver_otp(settings, data.phone, challenge_id, code)
        except Exception:
            db.execute(update(OtpChallenge).where(
                OtpChallenge.phone == data.phone,
                OtpChallenge.challenge_id == challenge_id,
            ).values(expires_at=0, sent_at=now - 60))
            db.commit()
            raise HTTPException(503, 'The verification message could not be sent. Please try again.')
        return {'challenge_id': challenge_id, 'expires_in': 300, 'resend_after': 60,
                'delivery': delivery,
                'message': 'Verification code requested.'}

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
        tokens = issue_session(db, user)
        db.commit()
        (otp_directory() / data.challenge_id).unlink(missing_ok=True)
        return {**tokens, 'user': profile(user, settings.environment)}

    @routes.post('/auth/refresh')
    def refresh(data: RefreshInput, db=Depends(database)):
        hashed = digest(data.refresh_token)
        # Atomic consumption serializes refreshes. Replaying a consumed token revokes
        # the entire family, including its replacement access and refresh tokens.
        claimed = db.execute(update(RefreshSession).where(
            RefreshSession.token_hash == hashed, RefreshSession.consumed == 0,
            RefreshSession.expires_at > int(time.time())).values(consumed=1))
        session = db.get(RefreshSession, hashed)
        if claimed.rowcount != 1:
            if session and session.consumed:
                revoke_family(db, session.family_id)
                db.commit()
            else:
                db.rollback()
            raise HTTPException(401, 'Session expired. Verify your phone again.')
        user = db.get(User, session.user_id)
        db.execute(update(AuthSession).where(AuthSession.family_id == session.family_id).values(expires_at=0))
        tokens = issue_session(db, user, session.family_id, session.expires_at)
        db.commit()
        return {**tokens, 'user': profile(user, settings.environment)}

    @routes.post('/me/profile')
    def save_profile(data: ProfileInput, user=Depends(actor), db=Depends(database)):
        user.display_name = data.display_name
        if data.username is not None:
            if data.username in {'sendoh', 'admin', 'support', 'official', 'help', 'security'}:
                raise HTTPException(422, 'Please choose another username.')
            if user.username and user.username != data.username:
                raise HTTPException(409, 'Your username cannot be changed yet.')
            user.username = data.username
        # Omitted fields preserve old clients and profile updates. Explicit null removes photo.
        if 'avatar' in data.model_fields_set:
            user.avatar = sanitize_avatar(data.avatar)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, 'That username is already taken. Choose another.')
        return profile(user, settings.environment)

    @routes.post('/auth/logout')
    def logout(user=Depends(actor), credentials=Depends(bearer), db=Depends(database)):
        session = db.get(AuthSession, digest(credentials.credentials))
        if session and session.family_id:
            revoke_family(db, session.family_id)
        elif settings.environment == 'development':
            db.execute(update(PushDevice).where(PushDevice.user_id == user.id,
                PushDevice.family_id == 'dev:' + user.id).values(active=0))
        db.execute(update(AuthSession).where(AuthSession.token_hash == digest(credentials.credentials)).values(expires_at=0))
        db.commit()
        return {'signed_out': True}

    return routes
