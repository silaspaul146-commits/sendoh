"""One provider transaction may confirm only one Sendoh reference."""
from sqlalchemy.exc import IntegrityError
from .models import ProviderReferenceClaim


def claim(db, application_hash, provider_id, reference):
    key = (application_hash, provider_id)
    old = db.get(ProviderReferenceClaim, key)
    if old:
        return old.sendoh_reference == reference
    try:
        with db.begin_nested():
            db.add(ProviderReferenceClaim(application_hash=application_hash,
                provider_id=provider_id, sendoh_reference=reference))
            db.flush()
        return True
    except IntegrityError:
        old = db.get(ProviderReferenceClaim, key)
        return old is not None and old.sendoh_reference == reference
