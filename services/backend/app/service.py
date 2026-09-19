import hashlib, json, secrets
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from .models import Collection, Participant, Activity, Idempotency, User

class Conflict(Exception): pass

def serialize(db, collection, web_url, public=False):
    result = dict(id=collection.id, name=collection.name, description=collection.description,
                  currency=collection.currency, target_amount=collection.target_amount,
                  deadline_at=collection.deadline_at.isoformat() if collection.deadline_at else None,
                  mode=collection.mode, expected_amount=collection.expected_amount,
                  status=collection.status, collected_amount=0)
    if public:
        result['organizer_name'] = db.get(User, collection.organizer_id).display_name
        result.pop('id')
        return result
    result['share_url'] = f'{web_url}/c/{collection.public_token}' if collection.status == 'ACTIVE' else None
    result['participants'] = [dict(id=p.id, name=p.name, expected_amount=p.expected_amount)
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
