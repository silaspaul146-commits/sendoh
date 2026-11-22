"""One payment-state contract for every screen.

Clients read `position` (one member) and `totals` (one collection) and must not
derive payment state from any other field. Rules:

- Membership is not payment: a member who has not joined has no payment state.
- Only provider-confirmed money is `confirmed_amount`. Money awaiting provider
  confirmation is `pending_amount`; it never counts toward progress or remaining.
- An open contribution (no expected amount) has no invented personal target.
- Legacy simulator records are excluded entirely.
- `environment` says which money this is. Until live payments exist it is SANDBOX.
- Cash recorded by the organizer counts toward a share and the amount raised, but is
  always reported as `cash_amount`, never merged into provider-confirmed money.
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


def _cash(db, collection_id, participant_id=None):
    from .models import CashRecord
    q = select(func.coalesce(func.sum(CashRecord.amount), 0)).where(CashRecord.collection_id == collection_id)
    if participant_id is not None:
        q = q.where(CashRecord.participant_id == participant_id)
    return int(db.scalar(q))


def member_position(db, participant, membership: str) -> dict:
    """membership is the effective invitation state (EXPIRED already applied)."""
    confirmed, pending = _sums(db, participant.collection_id, participant.id)
    cash = _cash(db, participant.collection_id, participant.id)
    paid = confirmed + cash
    expected = participant.expected_amount
    remaining = max(0, expected - paid) if expected else None
    if membership != 'ACCEPTED' and paid == 0 and pending == 0:
        state = {'PENDING': 'INVITED', 'DECLINED': 'DECLINED', 'CANCELLED': 'CANCELLED',
                 'EXPIRED': 'EXPIRED'}.get(membership, 'NOT_JOINED')
    elif pending > 0:
        state = 'CONFIRMING'
    elif paid == 0:
        state = 'NOT_STARTED'
    elif remaining is None:
        state = 'CONTRIBUTED'
    elif remaining > 0:
        state = 'PARTIAL'
    else:
        state = 'FULFILLED'
    return dict(state=state, membership=membership, environment=ENVIRONMENT,
                confirmed_amount=confirmed, pending_amount=pending,
                # Cash is the organizer's declaration, reported separately from MeSomb evidence.
                cash_amount=cash, paid_amount=paid,
                expected_amount=expected, remaining_amount=remaining)


def collection_totals(db, collection) -> dict:
    confirmed, pending = _sums(db, collection.id)
    cash = _cash(db, collection.id)
    raised = confirmed + cash
    target = collection.target_amount
    return dict(environment=ENVIRONMENT, confirmed_amount=confirmed, pending_amount=pending,
                cash_amount=cash, raised_amount=raised, target_amount=target,
                remaining_amount=max(0, target - raised) if target else None,
                target_reached=bool(target) and raised >= target)
