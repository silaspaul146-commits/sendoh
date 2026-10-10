"""Private notifications. Creation shares the business transaction."""
import hashlib
import time
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select, update, func, or_, and_
from sqlalchemy.exc import IntegrityError
from .models import (Notification, PushDevice, PushDelivery, Participant, Collection,
                     PhoneIdentity, AuthSession, RefreshSession, User)

KINDS = {
    'INVITED': 'You have a collection invitation',
    'ACCEPTED': 'Someone joined your collection',
    'DECLINED': 'Someone declined your invitation',
    'CANCELLED': 'A collection invitation was cancelled',
}

def emit(db, recipient, participant, kind, deliver=True):
    if not recipient:
        return
    event = f'{participant.id}:{participant.invitation_version}:{kind}:{recipient}'
    if db.scalar(select(Notification.id).where(Notification.event_key == event)):
        return
    now = int(time.time())
    # Savepoint handles overlapping phone-invitation materialization safely.
    try:
        with db.begin_nested():
            n = Notification(user_id=recipient, collection_id=participant.collection_id,
                participant_id=participant.id, invitation_version=participant.invitation_version,
                kind=kind, event_key=event, created_at=now)
            db.add(n)
            db.flush()
            devices = db.scalars(select(PushDevice).where(PushDevice.user_id == recipient,
                PushDevice.active == 1, PushDevice.expires_at > now)).all() if deliver else []
            for device in devices:
                db.add(PushDelivery(notification_id=n.id, device_id=device.id,
                    token_hash=device.token_hash, family_id=device.family_id, due_at=now))
            db.flush()
    except IntegrityError:
        if not db.scalar(select(Notification.id).where(Notification.event_key == event)):
            raise

def materialize_invitations(db, user):
    phone = db.scalar(select(PhoneIdentity.phone).where(PhoneIdentity.user_id == user.id))
    target = Participant.invited_user_id == user.id
    if phone:
        target = or_(target, and_(Participant.invited_user_id.is_(None), Participant.invited_phone == phone))
    for p in db.scalars(select(Participant).join(Collection).where(target,
        Participant.invitation_state == 'PENDING', Participant.expires_at > int(time.time()),
        Collection.status == 'ACTIVE').limit(200)):
        # Backfill the inbox without a burst of historical push alerts.
        emit(db, user.id, p, 'INVITED', deliver=False)

def serialize(db, n):
    c = db.get(Collection, n.collection_id)
    p = db.get(Participant, n.participant_id)
    available = bool(p and c and c.status == 'ACTIVE' and
        p.invitation_version == n.invitation_version and p.invitation_state == 'PENDING' and
        (p.expires_at or 0) > int(time.time()))
    return dict(id=n.id, kind=n.kind, title=KINDS[n.kind], collection_id=n.collection_id,
        collection_name=c.name if c else 'Collection', participant_id=n.participant_id,
        created_at=n.created_at, read_at=n.read_at,
        invitation_available=available if n.kind == 'INVITED' else False)

class RegisterDevice(BaseModel):
    model_config = ConfigDict(extra='forbid')
    token: str = Field(min_length=20, max_length=4096, pattern=r'^\S+$')
    platform: Literal['android', 'ios']

def family_for(db, user, credentials, environment):
    session = db.get(AuthSession, hashlib.sha256(credentials.credentials.encode()).hexdigest())
    if session and session.family_id:
        refresh = db.scalar(select(RefreshSession).where(RefreshSession.family_id == session.family_id,
            RefreshSession.consumed == 0, RefreshSession.expires_at > int(time.time())))
        if refresh:
            return session.family_id, refresh.expires_at
        raise HTTPException(401, 'Sign in again to enable notifications.')
    if environment == 'development':
        return 'dev:' + user.id, int(time.time()) + 86400
    raise HTTPException(401, 'Sign in again to enable notifications.')

def router(database, actor, bearer, settings, push_enabled):
    routes = APIRouter(prefix='/api/v1/me')

    @routes.get('/notifications')
    def inbox(before: str | None = Query(default=None, max_length=36),
              user=Depends(actor), db=Depends(database)):
        materialize_invitations(db, user)
        db.commit()
        query = select(Notification).where(Notification.user_id == user.id)
        if before:
            cursor = db.scalar(select(Notification).where(Notification.id == before, Notification.user_id == user.id))
            if not cursor:
                raise HTTPException(404, 'Notification not found.')
            query = query.where(or_(Notification.created_at < cursor.created_at,
                and_(Notification.created_at == cursor.created_at, Notification.id < cursor.id)))
        rows = db.scalars(query.order_by(Notification.created_at.desc(), Notification.id.desc()).limit(51)).all()
        unread = db.scalar(select(func.count()).select_from(Notification).where(
            Notification.user_id == user.id, Notification.read_at.is_(None)))
        return dict(items=[serialize(db, n) for n in rows[:50]], unread_count=unread,
                    next_cursor=rows[49].id if len(rows) > 50 else None, push_available=push_enabled)

    @routes.post('/notifications/{notification_id}/read')
    def read(notification_id: str, user=Depends(actor), db=Depends(database)):
        n = db.scalar(select(Notification).where(Notification.id == notification_id, Notification.user_id == user.id))
        if not n:
            raise HTTPException(404, 'Notification not found.')
        db.execute(update(Notification).where(Notification.id == n.id, Notification.read_at.is_(None))
                   .values(read_at=int(time.time())))
        db.commit()
        return {'ok': True}

    @routes.post('/push-devices/register')
    def register(data: RegisterDevice, user=Depends(actor), credentials=Depends(bearer), db=Depends(database)):
        if not push_enabled:
            raise HTTPException(409, 'Push alerts are not configured yet. Your inbox still works.')
        family, expiry = family_for(db, user, credentials, settings.environment)
        hashed = hashlib.sha256(data.token.encode()).hexdigest()
        # Lock the account to serialize its device-limit check on PostgreSQL.
        db.scalar(select(User).where(User.id == user.id).with_for_update())
        device = db.scalar(select(PushDevice).where(PushDevice.token_hash == hashed).with_for_update())
        now = int(time.time())
        # A refresh-token family belongs to one app installation/login. Token
        # rotation must replace that family's old registration, not consume a
        # new device slot. Old queued jobs are safely skipped by the worker.
        db.execute(update(PushDevice).where(PushDevice.user_id == user.id,
            PushDevice.family_id == family, PushDevice.token_hash != hashed).values(active=0))
        count = db.scalar(select(func.count()).select_from(PushDevice).where(PushDevice.user_id == user.id,
            PushDevice.active == 1, PushDevice.expires_at > now, PushDevice.token_hash != hashed))
        if count >= 5:
            raise HTTPException(409, 'Push alerts are enabled on five devices. Disable one first.')
        if device is None:
            device = PushDevice(token_hash=hashed)
            db.add(device)
        device.user_id, device.family_id = user.id, family
        device.token, device.platform, device.active = data.token, data.platform, 1
        device.updated_at, device.expires_at = now, expiry
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, 'Device registration changed. Please retry.')
        return {'id': device.id, 'enabled': True}

    @routes.post('/push-devices/disable')
    def disable(user=Depends(actor), credentials=Depends(bearer), db=Depends(database)):
        family, _ = family_for(db, user, credentials, settings.environment)
        db.execute(update(PushDevice).where(PushDevice.user_id == user.id, PushDevice.family_id == family)
                   .values(active=0))
        db.commit()
        return {'ok': True}

    return routes
