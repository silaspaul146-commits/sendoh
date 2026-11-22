"""One payment-state contract for every screen.

Clients read `position` (one member) and `totals` (one collection) and must not
derive payment state from any other field. Rules:

- Membership is not payment: a member who has not joined has no payment state.
- Only provider-confirmed money is `confirmed_amount`. Money awaiting provider
  confirmation is `pending_amount`; it never counts toward progress or remaining.
- An open contribution (no expected amount) has no invented personal target.
- Legacy simulator records are excluded entirely.
- `environment` says which money this is. Until live payments exist it is SANDBOX.
"""
from sqlalchemy import select, func
from .models import ProviderPayment

ENVIRONMENT = 'SANDBOX'


def money(amount: int) -> str:
    return f'{amount:,} FCFA'


def _sums(db, collection_id, participant_id=None):
    def total(status):
        q = select(func.coalesce(func.sum(ProviderPayment.amount), 0)).where(
            ProviderPayment.collection_id == collection_id,
            ProviderPayment.mode == ENVIRONMENT, ProviderPayment.status == status)
        if participant_id is not None:
            q = q.where(ProviderPayment.participant_id == participant_id)
        return int(db.scalar(q))
    return total('SUCCEEDED'), total('PENDING')


def member_position(db, participant, membership: str) -> dict:
    """membership is the effective invitation state (EXPIRED already applied)."""
    confirmed, pending = _sums(db, participant.collection_id, participant.id)
    expected = participant.expected_amount
    remaining = max(0, expected - confirmed) if expected else None
    if membership != 'ACCEPTED' and confirmed == 0 and pending == 0:
        state = {'PENDING': 'INVITED', 'DECLINED': 'DECLINED', 'CANCELLED': 'CANCELLED',
                 'EXPIRED': 'EXPIRED'}.get(membership, 'NOT_JOINED')
    elif pending > 0:
        state = 'CONFIRMING'
    elif confirmed == 0:
        state = 'NOT_STARTED'
    elif remaining is None:
        state = 'CONTRIBUTED'
    elif remaining > 0:
        state = 'PARTIAL'
    else:
        state = 'FULFILLED'
    return dict(state=state, membership=membership, environment=ENVIRONMENT,
                confirmed_amount=confirmed, pending_amount=pending,
                expected_amount=expected, remaining_amount=remaining)


def collection_totals(db, collection) -> dict:
    confirmed, pending = _sums(db, collection.id)
    target = collection.target_amount
    return dict(environment=ENVIRONMENT, confirmed_amount=confirmed, pending_amount=pending,
                target_amount=target,
                remaining_amount=max(0, target - confirmed) if target else None,
                target_reached=bool(target) and confirmed >= target,
                # Cash is recorded at close and will be reported separately, never merged.
                cash_amount=None)
