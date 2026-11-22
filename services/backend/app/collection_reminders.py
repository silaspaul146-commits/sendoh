"""Organizer-requested reminders for accepted, outstanding members."""
import time
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from .models import Collection, Participant, Notification
from .service import participant_summary
from .notifications import emit

COOLDOWN = 86400
KIND = 'CONTRIBUTION_REMINDER'


def outstanding(db, collection, participant):
    if not collection or collection.status != 'ACTIVE' or not participant:
        return False
    if (participant.invitation_state != 'ACCEPTED' or not participant.user_id
            or participant.user_id == collection.organizer_id):
        return False
    summary = participant_summary(db, participant)
    return (not summary['sandbox_payment_pending']
            and summary['sandbox_payment_status'] in ('Unpaid', 'Partial'))


def eligible(db, collection, now):
    recent = set(db.scalars(select(Notification.participant_id).where(
        Notification.collection_id == collection.id,
        Notification.kind == KIND, Notification.created_at > now - COOLDOWN)))
    return [p for p in db.scalars(select(Participant).where(
        Participant.collection_id == collection.id))
        if p.id not in recent and outstanding(db, collection, p)]


def router(database, actor):
    routes = APIRouter(prefix='/api/v1/collections')

    def owned(db, collection_id, user):
        collection = db.scalar(select(Collection).where(
            Collection.id == collection_id, Collection.organizer_id == user.id
        ).with_for_update())
        if collection is None:
            raise HTTPException(404, 'Collection not found.')
        if collection.status != 'ACTIVE':
            raise HTTPException(409, 'Only open collections can send reminders.')
        return collection

    @routes.get('/{collection_id}/reminders')
    def preview(collection_id: str, user=Depends(actor), db=Depends(database)):
        collection = owned(db, collection_id, user)
        return {'eligible_count': len(eligible(db, collection, int(time.time()))),
                'cooldown_hours': 24}

    @routes.post('/{collection_id}/reminders')
    def remind(collection_id: str, user=Depends(actor), db=Depends(database)):
        collection = owned(db, collection_id, user)
        now = int(time.time())
        members = eligible(db, collection, now)
        for member in members:
            # The collection row lock serializes the cooldown check on PostgreSQL.
            # The event key also de-duplicates same-day retries.
            emit(db, member.user_id, member, KIND,
                 event_id=f'{collection.id}:{member.id}:{now // COOLDOWN}')
        db.commit()
        return {'reminded_count': len(members), 'cooldown_hours': 24}

    return routes
