import hashlib, json, secrets, time
from sqlalchemy import select, func
from sqlalchemy.exc import IntegrityError
from .models import Collection, Participant, Activity, Idempotency, User, TestPayment

class Conflict(Exception): pass

from .contribution_state import member_position, collection_totals, current_round

def participant_state(p):
    if p.invitation_state == 'PENDING' and (p.expires_at or 0) <= int(time.time()):
        return 'EXPIRED'
    return p.invitation_state

def participant_summary(db, p):
    from .mesomb_payments import sandbox_total
    from .models import ProviderPayment
    member = db.get(User, p.user_id) if p.user_id else None
    paid = int(db.scalar(select(func.coalesce(func.sum(TestPayment.amount), 0)).where(TestPayment.participant_id == p.id, TestPayment.status == 'SUCCEEDED')))
    state = 'Unpaid' if paid == 0 else 'Partial' if p.expected_amount and paid < p.expected_amount else 'Paid'
    sandbox_paid = sandbox_total(db, p.collection_id, p.id)
    # Awaiting provider confirmation: shown beside confirmed money, never added to it.
    sandbox_pending_amount = int(db.scalar(select(func.coalesce(func.sum(ProviderPayment.amount), 0)).where(
        ProviderPayment.participant_id == p.id, ProviderPayment.mode == 'SANDBOX',
        ProviderPayment.status == 'PENDING', current_round(ProviderPayment))))
    sandbox_pending = sandbox_pending_amount > 0
    sandbox_state = ('Unpaid' if sandbox_paid == 0 else
                     'Partial' if p.expected_amount and sandbox_paid < p.expected_amount else 'Paid')
    return dict(sandbox_paid_amount=sandbox_paid,
                sandbox_payment_status=sandbox_state, sandbox_payment_pending=sandbox_pending,
                sandbox_pending_amount=sandbox_pending_amount, test_paid_amount=paid, test_payment_status=state, id=p.id, name=member.display_name if member else p.name,
                expected_amount=p.expected_amount, user_id=p.user_id,
                username=member.username if member else None,
                avatar=member.avatar if member else None,
                invitation_state=participant_state(p),
                invited_phone_hint=('••••••' + p.invited_phone[-3:]) if p.invited_phone else None,
                identity_verified=member is not None,
                position=member_position(db, p, participant_state(p)))

def serialize(db, collection, web_url, public=False):
    from .mesomb_payments import sandbox_total
    result = dict(id=collection.id, name=collection.name, description=collection.description,
                  currency=collection.currency, target_amount=collection.target_amount,
                  deadline_at=collection.deadline_at.isoformat() if collection.deadline_at else None,
                  mode=collection.mode, expected_amount=collection.expected_amount,
                  status=collection.status, collected_amount=0)
    result['sandbox_collected_amount'] = sandbox_total(db, collection.id)
    result['totals'] = collection_totals(db, collection)
    result['recurring'] = bool(collection.recurring)
    result['round'] = collection.round
    result['test_collected_amount'] = int(db.scalar(select(func.coalesce(func.sum(TestPayment.amount), 0)).where(TestPayment.collection_id == collection.id, TestPayment.status == 'SUCCEEDED')))
    if public:
        organizer = db.get(User, collection.organizer_id)
        result['organizer_name'] = organizer.display_name
        result['organizer_handle'] = '@' + organizer.username if organizer.username else None
        result.pop('id')
        return result
    result['share_url'] = f'{web_url}/c/{collection.public_token}' if collection.status == 'ACTIVE' else None
    result['participants'] = [participant_summary(db, p)
        for p in db.scalars(select(Participant).where(Participant.collection_id == collection.id))]
    return result

def create_collection(db, actor, key, data, web_url):
    fingerprint = hashlib.sha256(json.dumps(data.model_dump(mode='json'), sort_keys=True).encode()).hexdigest()
    def existing():
        record = db.scalar(select(Idempotency).where(Idempotency.actor_id == actor, Idempotency.key == key))
        if record:
            if record.fingerprint != fingerprint: raise Conflict('Idempotency key already used with different input')
            return record.response
    cached = existing()
    if cached is not None: return cached
    record = Idempotency(actor_id=actor, key=key, fingerprint=fingerprint)
    try:
        db.add(record)
        db.flush()  # Uniqueness serializes concurrent requests before creating business records.
    except IntegrityError:
        db.rollback()
        cached = existing()
        if cached is not None: return cached
        raise
    collection = Collection(organizer_id=actor, public_token=secrets.token_urlsafe(24),
        **data.model_dump(exclude={'participants', 'publish'}), status='ACTIVE' if data.publish else 'DRAFT')
    db.add(collection)
    db.flush()
    for participant in data.participants:
        db.add(Participant(collection_id=collection.id, name=participant.name,
            expected_amount=participant.expected_amount or data.expected_amount))
    db.add(Activity(organizer_id=actor, collection_id=collection.id,
        message=f'Created {collection.name}'))
    db.flush()
    record.response = serialize(db, collection, web_url)
    db.commit()
    return record.response
