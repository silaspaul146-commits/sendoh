"""Deleting a Sendoh account.

Deletion removes what identifies the person: name, username, photo, the phone
number they sign in with, sessions and push devices. Money records stay, because
other people's receipts and the organizer's ledger depend on them: payments,
settlements and cash records keep their amounts, dates and the Mobile Money
number used, as financial records. The person's name on them becomes
"Deleted user" / "Former member".

Deletion is refused while money involving the person is still moving, so no
payment, payout or collection is left without an owner.
"""
import hashlib
import secrets
import time

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict
from sqlalchemy import or_, select, update

from .contribution_state import collection_totals
from .models import (AuthSession, Collection, MoneyRequest, NearCode, OtpChallenge, Participant,
                     PersonExecution, PersonOrder, PhoneIdentity, ProviderPayment, PushDevice,
                     RefreshSession, Settlement, User)

DELETED_NAME = 'Deleted user'
FORMER_MEMBER = 'Former member'


class DeleteInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    confirm: str


def blockers(db, user) -> list[dict]:
    """Everything that must finish before the account can go, in plain words."""
    found = []
    if db.scalar(select(ProviderPayment.id).where(ProviderPayment.payer_id == user.id,
                                                  ProviderPayment.status == 'PENDING').limit(1)):
        found.append(dict(code='PAYMENT_CONFIRMING',
                          message='A payment you made is still being confirmed.'))
    moving = db.scalar(select(PersonExecution.order_id)
                       .join(PersonOrder, PersonOrder.id == PersonExecution.order_id)
                       .where(or_(PersonOrder.payer_id == user.id, PersonOrder.beneficiary_id == user.id),
                              PersonExecution.state.not_in(('SUCCEEDED', 'FAILED'))).limit(1))
    if moving:
        found.append(dict(code='TRANSFER_IN_PROGRESS',
                          message='A payment to or from you is still on its way.'))
    if db.scalar(select(Settlement.id).where(Settlement.organizer_id == user.id,
                                             Settlement.state != 'DELIVERED').limit(1)):
        found.append(dict(code='PAYOUT_IN_PROGRESS',
                          message='A collection payout is still being sent.'))
    for c in db.scalars(select(Collection).where(Collection.organizer_id == user.id,
                                                 Collection.status.in_(('ACTIVE', 'CLOSED')))):
        totals = collection_totals(db, c)
        if totals['raised_amount'] > 0 or totals['pending_amount'] > 0:
            found.append(dict(code='COLLECTION_HOLDS_MONEY', collection_id=c.id, collection_name=c.name,
                              message=f'Close and settle "{c.name}" first.'))
    return found


def delete_account(db, user):
    now = int(time.time())
    phone = db.scalar(select(PhoneIdentity.phone).where(PhoneIdentity.user_id == user.id))
    # Collections with no money in them simply stop taking contributions.
    db.execute(update(Collection).where(Collection.organizer_id == user.id,
                                        Collection.status.in_(('DRAFT', 'ACTIVE')))
               .values(status='CLOSED'))
    db.execute(update(MoneyRequest).where(
        or_(MoneyRequest.requester_id == user.id, MoneyRequest.recipient_id == user.id),
        MoneyRequest.status == 'PENDING').values(status='CANCELLED'))
    db.execute(update(PersonOrder).where(
        or_(PersonOrder.payer_id == user.id, PersonOrder.beneficiary_id == user.id),
        PersonOrder.status == 'READY').values(status='CANCELLED'))
    db.execute(update(NearCode).where(NearCode.user_id == user.id).values(expires_at=0))
    db.execute(update(Participant).where(Participant.user_id == user.id).values(name=FORMER_MEMBER))
    if phone:
        # Invitations still waiting for this number are withdrawn.
        db.execute(update(Participant).where(Participant.invited_phone == phone,
                                             Participant.invitation_state == 'PENDING')
                   .values(invitation_state='CANCELLED'))
        db.execute(OtpChallenge.__table__.delete().where(OtpChallenge.phone == phone))
    db.execute(PhoneIdentity.__table__.delete().where(PhoneIdentity.user_id == user.id))
    db.execute(update(AuthSession).where(AuthSession.user_id == user.id).values(expires_at=0))
    db.execute(update(RefreshSession).where(RefreshSession.user_id == user.id)
               .values(consumed=1, expires_at=0))
    db.execute(update(PushDevice).where(PushDevice.user_id == user.id).values(active=0, token='', expires_at=now))
    user.display_name = DELETED_NAME
    user.username = None
    user.avatar = None
    user.token_hash = hashlib.sha256(secrets.token_urlsafe(48).encode()).hexdigest()


def router(database, actor):
    routes = APIRouter(prefix='/api/v1/me')

    @routes.get('/account/deletion')
    def check(user=Depends(actor), db=Depends(database)):
        """What deleting would do now, before the person confirms."""
        return dict(can_delete=not blockers(db, user), blockers=blockers(db, user))

    @routes.post('/account/delete')
    def delete(data: DeleteInput, user=Depends(actor), db=Depends(database)):
        if data.confirm != 'DELETE':
            raise HTTPException(422, 'Confirm deletion to continue.')
        found = blockers(db, user)
        if found:
            raise HTTPException(409, found[0]['message'])
        delete_account(db, user)
        db.commit()
        return dict(deleted=True)

    return routes
