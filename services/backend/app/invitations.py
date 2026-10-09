"""Account-bound invitations. Public collection tokens never grant membership."""
import hashlib
import json
import time
from typing import Literal
from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from sqlalchemy import select, update, or_, and_, func
from sqlalchemy.exc import IntegrityError
from .models import User, PhoneIdentity, Participant, Collection, Activity, Idempotency, InvitationRate
from .schemas import Money
from .service import participant_state, participant_summary, serialize

class InviteInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    username: str | None = Field(default=None, pattern=r'^[a-z][a-z0-9_]{2,23}$')
    phone: str | None = Field(default=None, pattern=r'^\+237[26][0-9]{8}$')
    name: str = Field(default='Invited participant', min_length=1, max_length=120)
    participant_id: str | None = Field(default=None, min_length=36, max_length=36)
    expected_amount: Money | None = None

    @field_validator('username', mode='before')
    @classmethod
    def normalize(cls, value):
        return value.strip().removeprefix('@').lower() if isinstance(value, str) else value

    @model_validator(mode='after')
    def one_identity(self):
        if (self.username is None) == (self.phone is None):
            raise ValueError('Supply exactly one username or phone.')
        return self

class DecisionInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    decision: Literal['accept', 'decline']

def recipient_filter(db, user):
    phone = db.scalar(select(PhoneIdentity.phone).where(PhoneIdentity.user_id == user.id))
    # A phone is only a fallback for an invite created before account registration.
    return or_(Participant.invited_user_id == user.id,
               and_(Participant.invited_user_id.is_(None), Participant.invited_phone == phone)) if phone else Participant.invited_user_id == user.id

def consume_rate(db, user):
    now = int(time.time())
    row = db.get(InvitationRate, user.id)
    if row is None:
        try:
            db.add(InvitationRate(user_id=user.id, window_start=now, count=1))
            db.commit()
            return
        except IntegrityError:
            db.rollback()
    # Database updates make the limit shared across server workers.
    reset = db.execute(update(InvitationRate).where(InvitationRate.user_id == user.id,
        InvitationRate.window_start <= now - 60).values(window_start=now, count=1))
    if reset.rowcount != 1:
        increment = db.execute(update(InvitationRate).where(InvitationRate.user_id == user.id,
            InvitationRate.count < 20).values(count=InvitationRate.count + 1))
        if increment.rowcount != 1:
            db.rollback()
            raise HTTPException(429, 'Please wait a minute before sending more invitations.')
    db.commit()

def invitation_view(db, p, c, web_url):
    # Recipient view contains only their own participant row, never the roster.
    info = serialize(db, c, web_url, public=True)
    return dict(id=p.id, collection_id=c.id, collection=info,
                participant_name=p.name, expected_amount=p.expected_amount,
                invitation_state=participant_state(p), expires_at=p.expires_at,
                share_url=f'{web_url}/c/{c.public_token}' if c.status == 'ACTIVE' else None)

def router(database, actor, web_url):
    routes = APIRouter(prefix='/api/v1')

    @routes.post('/collections/{collection_id}/invitations', status_code=201)
    def invite(collection_id: str, data: InviteInput,
               idempotency_key: str = Header(min_length=8, max_length=120),
               user=Depends(actor), db=Depends(database)):
        if not user.username:
            raise HTTPException(409, 'Complete your profile first.')
        owned = db.scalar(select(Collection).where(Collection.id == collection_id, Collection.organizer_id == user.id))
        if not owned:
            raise HTTPException(404, 'Collection not found.')
        consume_rate(db, user)
        fingerprint = hashlib.sha256(json.dumps({'operation':'invite', 'collection':collection_id,
            'body':data.model_dump()}, sort_keys=True).encode()).hexdigest()
        existing = db.scalar(select(Idempotency).where(Idempotency.actor_id == user.id, Idempotency.key == idempotency_key))
        if existing:
            if existing.fingerprint != fingerprint:
                raise HTTPException(409, 'This request key was used for different input.')
            return existing.response
        record = Idempotency(actor_id=user.id, key=idempotency_key, fingerprint=fingerprint)
        try:
            db.add(record)
            db.flush()
        except IntegrityError:
            db.rollback()
            existing = db.scalar(select(Idempotency).where(Idempotency.actor_id == user.id, Idempotency.key == idempotency_key))
            if existing and existing.fingerprint == fingerprint:
                return existing.response
            raise HTTPException(409, 'This request key was used for different input.')
        # Serializes roster mutation/count checks with other invitation operations.
        c = db.scalar(select(Collection).where(Collection.id == collection_id).with_for_update())
        if c.status != 'ACTIVE':
            raise HTTPException(409, 'Publish this collection before inviting people.')
        if c.mode == 'ANY_AMOUNT' and data.expected_amount is not None:
            raise HTTPException(422, 'Any-amount collections cannot impose an expectation.')
        target = None
        phone = data.phone
        if data.username:
            target = db.scalar(select(User).where(User.username == data.username))
            if not target:
                raise HTTPException(404, 'Username not found. Check it or invite by phone.')
            phone = db.scalar(select(PhoneIdentity.phone).where(PhoneIdentity.user_id == target.id))
        else:
            identity = db.get(PhoneIdentity, phone)
            if identity:
                target = db.get(User, identity.user_id)
        if target and target.id == user.id:
            raise HTTPException(409, 'You already organize this collection.')
        conditions = []
        if target:
            conditions += [Participant.invited_user_id == target.id, Participant.user_id == target.id]
        if phone:
            conditions.append(Participant.invited_phone == phone)
        duplicate = db.scalar(select(Participant).where(Participant.collection_id == c.id, or_(*conditions)))
        p = db.scalar(select(Participant).where(Participant.id == data.participant_id,
            Participant.collection_id == c.id)) if data.participant_id else None
        if data.participant_id and not p:
            raise HTTPException(404, 'Participant not found in this collection.')
        if duplicate and p and duplicate.id != p.id:
            raise HTTPException(409, 'That person already has a participant entry. No rows were merged.')
        p = p or duplicate
        if p and p.invitation_state == 'DECLINED':
            raise HTTPException(409, 'This person declined. Do not resend this invitation.')
        if p and participant_state(p) in ('PENDING', 'ACCEPTED'):
            # A bound row cannot be silently reassigned to another identity.
            if p != duplicate:
                raise HTTPException(409, 'Cancel the pending invitation before choosing another person.')
            record.response = participant_summary(db, p)
            db.commit()
            return record.response
        if p is None:
            count = db.scalar(select(func.count()).select_from(Participant).where(Participant.collection_id == c.id))
            if count >= 200:
                raise HTTPException(409, 'This collection has reached 200 participants.')
            p = Participant(collection_id=c.id, name=data.name,
                            expected_amount=data.expected_amount or c.expected_amount)
            db.add(p)
        elif data.expected_amount is not None:
            p.expected_amount = data.expected_amount
        p.name = target.display_name if target and target.display_name else p.name
        p.invited_user_id = target.id if target else None
        p.invited_phone = phone
        p.invitation_state = 'PENDING'
        p.invited_at = int(time.time())
        p.expires_at = p.invited_at + 14 * 86400
        try:
            db.flush()
            record.response = participant_summary(db, p)
            db.add(Activity(organizer_id=user.id, collection_id=c.id, message='Sent a participant invitation'))
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, 'That person already has an invitation or membership.')
        return record.response

    @routes.get('/me/invitations')
    def inbox(user=Depends(actor), db=Depends(database)):
        rows = db.execute(select(Participant, Collection).join(Collection, Participant.collection_id == Collection.id)
            .where(recipient_filter(db, user), Participant.invitation_state == 'PENDING',
                   Participant.expires_at > int(time.time()), Collection.status == 'ACTIVE')
            .order_by(Participant.invited_at.desc()).limit(200)).all()
        return [invitation_view(db, p, c, web_url) for p, c in rows]

    @routes.post('/me/invitations/{invitation_id}/respond')
    def respond(invitation_id: str, data: DecisionInput, user=Depends(actor), db=Depends(database)):
        if not user.username:
            raise HTTPException(409, 'Complete your profile first.')
        probe = db.scalar(select(Participant).where(Participant.id == invitation_id, recipient_filter(db, user)))
        if not probe:
            raise HTTPException(404, 'Invitation not found.')
        c = db.scalar(select(Collection).where(Collection.id == probe.collection_id).with_for_update())
        p = db.scalar(select(Participant).where(Participant.id == invitation_id,
            recipient_filter(db, user)).execution_options(populate_existing=True).with_for_update())
        if not p:
            raise HTTPException(404, 'Invitation not found.')
        desired = 'ACCEPTED' if data.decision == 'accept' else 'DECLINED'
        if p.invitation_state == desired:
            return invitation_view(db, p, c, web_url)
        if participant_state(p) != 'PENDING' or c.status != 'ACTIVE':
            raise HTTPException(409, 'This invitation is no longer available.')
        try:
            values = dict(invitation_state=desired, invited_user_id=user.id)
            if desired == 'ACCEPTED':
                values.update(user_id=user.id, name=user.display_name)
            claimed = db.execute(update(Participant).where(Participant.id == p.id,
                Participant.invitation_state == 'PENDING', Participant.expires_at > int(time.time()),
                recipient_filter(db, user)).values(**values))
            if claimed.rowcount != 1:
                db.rollback()
                raise HTTPException(409, 'This invitation has already changed. Refresh your invitations.')
            db.add(Activity(organizer_id=c.organizer_id, collection_id=c.id,
                message=f'{user.display_name[:120]} {"joined the collection" if desired == "ACCEPTED" else "declined an invitation"}'))
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, 'You already have a participant entry. Ask the organizer to review it.')
        return invitation_view(db, p, c, web_url)

    @routes.get('/me/joined-collections')
    def joined(user=Depends(actor), db=Depends(database)):
        rows = db.execute(select(Participant, Collection).join(Collection, Participant.collection_id == Collection.id)
            .where(Participant.user_id == user.id, Participant.invitation_state == 'ACCEPTED')
            .order_by(Participant.invited_at.desc()).limit(200)).all()
        return [invitation_view(db, p, c, web_url) for p, c in rows]

    @routes.post('/collections/{collection_id}/invitations/{invitation_id}/cancel')
    def cancel(collection_id: str, invitation_id: str, user=Depends(actor), db=Depends(database)):
        c = db.scalar(select(Collection).where(Collection.id == collection_id,
            Collection.organizer_id == user.id).with_for_update())
        if not c:
            raise HTTPException(404, 'Collection not found.')
        p = db.scalar(select(Participant).where(Participant.id == invitation_id,
            Participant.collection_id == c.id).with_for_update())
        if not p:
            raise HTTPException(404, 'Invitation not found.')
        if p.invitation_state == 'CANCELLED':
            return participant_summary(db, p)
        if p.invitation_state != 'PENDING':
            raise HTTPException(409, 'Only pending invitations can be cancelled.')
        changed = db.execute(update(Participant).where(Participant.id == p.id,
            Participant.invitation_state == 'PENDING').values(invitation_state='CANCELLED'))
        if changed.rowcount != 1:
            db.rollback()
            raise HTTPException(409, 'This invitation has already changed. Refresh the collection.')
        db.add(Activity(organizer_id=user.id, collection_id=c.id, message='Cancelled a participant invitation'))
        db.commit()
        return participant_summary(db, p)

    return routes
