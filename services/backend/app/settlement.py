"""Close a collection, record cash, and send the Mobile Money proceeds to the organizer.

Answers three questions with server-computed figures:
- How much did we raise?  Mobile Money confirmed by MeSomb + cash recorded by the
  organizer, always reported separately.
- What will reach my phone?  Confirmed Mobile Money net of the provider fees MeSomb
  reported, minus Sendoh's settlement fee and any payout cost. Cash is not sent:
  the organizer already holds it, and no Sendoh fee applies to it.
- Did my contribution count?  Member positions include their recorded cash.

Money rules (same as person payments):
- The settlement row, which is the payout reservation, commits before the deposit
  is sent. Only that request sends. Recovery only looks the payout up; a committed
  payout is never sent again, whatever happens.
- "Delivered" only after MeSomb lookup evidence matches amount, operator, receiver.
- No default tariff: without an explicit policy and the sandbox flag, settlement is
  unavailable rather than free.
"""
import hashlib
import json
import os
import time
import uuid
from decimal import Decimal, ROUND_FLOOR
from types import SimpleNamespace

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import select, update, func
from sqlalchemy.exc import IntegrityError

from .models import (Activity, CashRecord, Collection, Participant, ProviderPayment,
                     Settlement, User)
from .contribution_state import money
from .notifications import notify
from .provider_claims import claim
from .providers.mesomb import ReconciliationRequired
from .receiving import current_destination, destination_current

FLAG = 'SENDOH_SANDBOX_SETTLEMENT_PAYOUTS'
POLICY_ENV = 'SENDOH_SANDBOX_SETTLEMENT_FEE_POLICY'
LIMIT = 1_000_000_000

BLOCKER_TEXT = {
    'PAYMENTS_CONFIRMING': 'Wait for payments that are still confirming.',
    'FEES_NOT_CONFIRMED': 'MeSomb has not yet reported fees for every payment.',
    'NOTHING_TO_SEND': 'There is no confirmed Mobile Money to send.',
    'RECEIVING_DETAILS_NEEDED': 'Add where you receive Mobile Money.',
    'SETTLEMENT_NOT_AVAILABLE': 'Settlement is not available yet.',
    'SANDBOX_RECEIVER_NOT_ALLOWED': 'Use an approved MeSomb sandbox test number to receive.',
    'PAYOUT_FEE_CONTRACT_NOT_VERIFIED': 'Payout fees are not yet supported.',
    'FEES_EXCEED_PROCEEDS': 'Fees are larger than the confirmed Mobile Money.',
    'NOT_OPEN': 'This collection is already closed.',
}


class SettlementPolicy(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True, frozen=True)
    version: str = Field(min_length=1, max_length=60, pattern=r'^[A-Za-z0-9_.-]+$')
    sendoh_bps: int = Field(ge=0, lt=10000)
    sendoh_min: int = Field(ge=0, le=LIMIT)
    sendoh_cap: int = Field(ge=0, le=LIMIT)
    payout_bps: int = Field(ge=0, lt=10000)
    payout_fixed: int = Field(ge=0, le=LIMIT)

    @model_validator(mode='after')
    def bounds(self):
        if self.sendoh_cap < self.sendoh_min:
            raise ValueError('Fee cap must not be below the minimum.')
        return self


def configured_policy():
    raw = os.getenv(POLICY_ENV)
    if not raw:
        return None
    try:
        return SettlementPolicy.model_validate_json(raw)
    except ValueError:
        return None  # Invalid configuration disables settlement, never "free".


def enabled(config):
    return config is not None and os.getenv(FLAG) == '1'


def ceiling_div(n, d):
    return (n + d - 1) // d


def masked(phone):
    return '••• ' + phone[-3:] if phone else None


def cash_by_participant(db, collection_id):
    return {r.participant_id: r for r in db.scalars(select(CashRecord).where(
        CashRecord.collection_id == collection_id))}


def raised(db, c):
    paid = list(db.scalars(select(ProviderPayment).where(
        ProviderPayment.collection_id == c.id, ProviderPayment.mode == 'SANDBOX',
        ProviderPayment.status == 'SUCCEEDED')))
    pending = int(db.scalar(select(func.count()).select_from(ProviderPayment).where(
        ProviderPayment.collection_id == c.id, ProviderPayment.status == 'PENDING')))
    mobile = sum(p.amount for p in paid)
    cash = sum(r.amount for r in cash_by_participant(db, c.id).values())
    unverified = sum(1 for p in paid if p.accounting_verified_at is None or p.confirmed_net is None)
    net = sum((Decimal(p.confirmed_net) for p in paid if p.confirmed_net is not None), Decimal(0))
    total = mobile + cash
    return dict(mobile_money=mobile, cash=cash, total=total, target=c.target_amount,
                target_reached=bool(c.target_amount) and total >= c.target_amount,
                pending_count=pending, _unverified=unverified, _net=net)


def quote(db, c, organizer_id, config, policy):
    r = raised(db, c)
    blockers = []
    if c.status != 'ACTIVE':
        blockers.append('NOT_OPEN')
    if r['pending_count']:
        blockers.append('PAYMENTS_CONFIRMING')
    if r['_unverified']:
        blockers.append('FEES_NOT_CONFIRMED')
    if r['mobile_money'] == 0:
        blockers.append('NOTHING_TO_SEND')
    dest = current_destination(db, organizer_id)
    if dest is None or not destination_current(db, dest):
        dest = None
        blockers.append('RECEIVING_DETAILS_NEEDED')
    if policy is None or not enabled(config):
        blockers.append('SETTLEMENT_NOT_AVAILABLE')
    elif dest is not None and dest.phone not in config.test_phones:
        blockers.append('SANDBOX_RECEIVER_NOT_ALLOWED')
    amounts = None
    if policy is not None and r['mobile_money'] > 0 and not r['_unverified']:
        gross = r['mobile_money']
        net_whole = int(r['_net'].to_integral_value(rounding=ROUND_FLOOR))
        sendoh = min(policy.sendoh_cap, max(policy.sendoh_min, ceiling_div(gross * policy.sendoh_bps, 10000)))
        # Payout cost is charged on what is sent; solve the smallest consistent cost.
        payout_cost = policy.payout_fixed + ceiling_div((net_whole - sendoh) * policy.payout_bps, 10000)
        payout = net_whole - sendoh - payout_cost
        if payout_cost:
            blockers.append('PAYOUT_FEE_CONTRACT_NOT_VERIFIED')
        if payout <= 0:
            blockers.append('FEES_EXCEED_PROCEEDS')
        else:
            amounts = dict(mobile_money=gross, provider_fees=str(Decimal(gross) - r['_net']),
                           sendoh_fee=sendoh, payout_cost=payout_cost,
                           # Whole-FCFA rounding of the provider net stays with the collection record.
                           rounding=str(r['_net'] - net_whole),
                           fees_total=gross - payout, payout_amount=payout,
                           cash=r['cash'], currency='XAF')
    public = {k: v for k, v in r.items() if not k.startswith('_')}
    return public, blockers, amounts, dest, policy


def settlement_view(s):
    if s is None:
        return None
    return dict(id=s.id, reference=s.id, state=s.state, payout_amount=s.payout_amount,
                method=s.method, destination=masked(s.phone), amounts=s.amounts,
                delivered=s.state == 'DELIVERED', review_reason=s.review_reason,
                environment='SANDBOX', created_at=s.created_at, updated_at=s.updated_at)


def notify_settlement(db, s, c):
    """Organizer and members hear about a settlement outcome exactly once."""
    if s.state == 'DELIVERED':
        notify(db, s.organizer_id, 'SETTLEMENT_DELIVERED', f'settlement:{s.id}:DELIVERED',
               collection_id=c.id, settlement_id=s.id)
        for p in db.scalars(select(Participant).where(Participant.collection_id == c.id,
                Participant.invitation_state == 'ACCEPTED')):
            if p.user_id and p.user_id != s.organizer_id:
                notify(db, p.user_id, 'COLLECTION_SETTLED', f'settlement:{s.id}:SETTLED:{p.user_id}',
                       collection_id=c.id, participant_id=p.id, settlement_id=s.id)
        db.add(Activity(organizer_id=s.organizer_id, collection_id=c.id,
            message=f'{money(s.payout_amount)} delivered to your {"MTN MoMo" if s.method == "MTN" else "Orange Money"} · Sandbox'))
    elif s.state == 'REVIEW':
        notify(db, s.organizer_id, 'SETTLEMENT_REVIEW', f'settlement:{s.id}:REVIEW:{s.review_reason}',
               collection_id=c.id, settlement_id=s.id)


def submit_once(sessions, api, settlement_id):
    # Only the request that just committed this settlement calls this.
    with sessions() as db:
        s = db.get(Settlement, settlement_id)
        args = dict(external_id=s.id, amount=s.payout_amount, receiver=s.phone, service=s.method)
    try:
        api.deposit(**args)
    except Exception:
        # Unknown outcome: never resend. Lookups decide.
        with sessions() as db:
            db.execute(update(Settlement).where(Settlement.id == settlement_id,
                Settlement.payout_status == 'PENDING').values(review_reason='SUBMISSION_UNCERTAIN'))
            db.commit()


def reconcile(sessions, config, api, settlement_id):
    from .person_execution import delivery_evidence
    owner, now = str(uuid.uuid4()), int(time.time())
    with sessions() as db:
        changed = db.execute(update(Settlement).where(Settlement.id == settlement_id,
            Settlement.application_hash == config.application_hash,
            Settlement.lease_until <= now, Settlement.next_check_at <= now)
            .values(lease_owner=owner, lease_until=now + 90))
        db.commit()
        if changed.rowcount != 1:
            return
        s = db.get(Settlement, settlement_id)
        leg = SimpleNamespace(amount=s.payout_amount, method=s.method, phone=s.phone, provider_id=s.provider_id)
    desired = transaction = None
    reason = None
    try:
        rows = api.lookup(settlement_id)
        if len(rows) != 1:
            reason = 'NO_MATCH_YET' if not rows else 'MULTIPLE_MATCHES'
        else:
            transaction = rows[0]
            desired, _, _ = delivery_evidence(transaction, leg)
    except ReconciliationRequired:
        reason = 'PAYOUT_EVIDENCE_UNVERIFIED'
    except Exception:
        reason = 'RECONCILIATION_ERROR'
    with sessions() as db:
        s = db.scalar(select(Settlement).where(Settlement.id == settlement_id,
            Settlement.lease_owner == owner).with_for_update())
        if s is None:
            return
        c = db.scalar(select(Collection).where(Collection.id == s.collection_id).with_for_update())
        s.attempts += 1
        s.updated_at = int(time.time())
        if reason is None and desired is not None:
            if not claim(db, config.application_hash, transaction['pk'], s.id):
                reason = 'DUPLICATE_PROVIDER_TRANSACTION'
            elif s.payout_status != 'PENDING' and desired not in (s.payout_status, 'REFUNDED'):
                reason = 'CONFLICTING_PROVIDER_OUTCOME'
        if reason is None and desired is not None:
            s.provider_id = transaction['pk']
            s.payout_status = desired
            if desired == 'SUCCEEDED' and s.state != 'DELIVERED':
                s.state, s.review_reason = 'DELIVERED', None
                c.status = 'SETTLED'
            elif desired == 'FAILED':
                # Funds stay with the collection; nobody is charged again.
                s.state, s.review_reason = 'REVIEW', 'PAYOUT_FAILED_FUNDS_RETAINED'
            elif desired == 'REFUNDED':
                s.state, s.review_reason = 'REVIEW', 'PAYOUT_REVERSED'
            elif desired == 'PENDING':
                s.review_reason = None
        elif reason == 'NO_MATCH_YET':
            # Keep SENDING; an uncertain submission keeps its note for support.
            if s.review_reason != 'SUBMISSION_UNCERTAIN':
                s.review_reason = None
        else:
            s.state, s.review_reason = 'REVIEW', reason
        s.next_check_at = s.updated_at + (min(3600, 15 * 2 ** min(s.attempts, 8))
                                          if s.payout_status == 'PENDING' else 86400)
        s.lease_until, s.lease_owner = 0, None
        notify_settlement(db, s, c)
        db.commit()


def run_due(sessions, config, api):
    now = int(time.time())
    with sessions() as db:
        ids = list(db.scalars(select(Settlement.id).where(
            Settlement.application_hash == config.application_hash,
            Settlement.next_check_at <= now, Settlement.lease_until <= now)
            .order_by(Settlement.next_check_at).limit(20)))
    for settlement_id in ids:
        reconcile(sessions, config, api, settlement_id)


class CashEntry(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)
    participant_id: str = Field(min_length=1, max_length=36)
    amount: int = Field(ge=0, le=LIMIT)  # 0 removes the record


class CashInput(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)
    entries: list[CashEntry] = Field(max_length=500)


class CloseAndSend(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)
    consent: str = Field(pattern='^CLOSE_AND_SEND$')
    payout_amount: int = Field(gt=0, le=LIMIT)


def router(database, actor, sessions, config):
    routes = APIRouter(prefix='/api/v1/collections')

    def organized(db, collection_id, user, lock=False):
        q = select(Collection).where(Collection.id == collection_id, Collection.organizer_id == user.id)
        c = db.scalar(q.with_for_update() if lock else q)
        if c is None:
            raise HTTPException(404, 'Collection not found.')
        return c

    def overview(db, c, user):
        s = db.scalar(select(Settlement).where(Settlement.collection_id == c.id))
        figures, blockers, amounts, dest, policy = quote(db, c, user.id, config, configured_policy())
        return dict(collection_status=c.status, raised=figures,
                    blockers=[] if s else [dict(code=b, message=BLOCKER_TEXT[b]) for b in blockers],
                    quote=None if s else amounts,
                    destination=dict(method=dest.method, masked=masked(dest.phone)) if dest else None,
                    settlement=settlement_view(s), policy_version=policy.version if policy else None,
                    environment='SANDBOX')

    @routes.get('/{collection_id}/settlement')
    def read(collection_id: str, user=Depends(actor), db=Depends(database)):
        return overview(db, organized(db, collection_id, user), user)

    @routes.post('/{collection_id}/cash')
    def record_cash(collection_id: str, data: CashInput, user=Depends(actor), db=Depends(database)):
        c = organized(db, collection_id, user, lock=True)
        if c.status != 'ACTIVE':
            raise HTTPException(409, 'Cash can only be changed before the collection is closed.')
        members = {p.id: p for p in db.scalars(select(Participant).where(Participant.collection_id == c.id))}
        existing = cash_by_participant(db, c.id)
        now = int(time.time())
        for entry in data.entries:
            p = members.get(entry.participant_id)
            if p is None or p.invitation_state in ('DECLINED', 'CANCELLED'):
                raise HTTPException(422, 'Cash can only be recorded for members of this collection.')
            record = existing.get(p.id)
            if entry.amount == 0:
                if record:
                    db.delete(record)
                continue
            if record and record.amount == entry.amount:
                continue
            if record:
                record.amount, record.updated_at, record.flagged_at = entry.amount, now, None
            else:
                record = CashRecord(collection_id=c.id, participant_id=p.id, amount=entry.amount,
                                    recorded_by=user.id, updated_at=now)
                db.add(record)
                db.flush()
            # Members see what was recorded in their name, so errors surface early.
            if p.user_id and p.user_id != user.id:
                notify(db, p.user_id, 'CASH_RECORDED', f'cash:{record.id}:{entry.amount}:{now}',
                       collection_id=c.id, participant_id=p.id)
        db.commit()
        return overview(db, c, user)

    @routes.post('/{collection_id}/cash/flag')
    def flag_cash(collection_id: str, user=Depends(actor), db=Depends(database)):
        p = db.scalar(select(Participant).where(Participant.collection_id == collection_id,
                                                Participant.user_id == user.id))
        record = db.scalar(select(CashRecord).where(CashRecord.participant_id == p.id)) if p else None
        if record is None:
            raise HTTPException(404, 'No cash is recorded for you in this collection.')
        if record.flagged_at is None:
            record.flagged_at = int(time.time())
            c = db.get(Collection, collection_id)
            notify(db, c.organizer_id, 'CASH_FLAGGED', f'cash-flag:{record.id}:{record.updated_at}',
                   collection_id=c.id, participant_id=p.id)
        db.commit()
        return dict(flagged=True)

    @routes.post('/{collection_id}/settlement')
    def close_and_send(collection_id: str, data: CloseAndSend, request: Request,
                       idempotency_key: str = Header(min_length=8, max_length=120),
                       user=Depends(actor), db=Depends(database)):
        replay = db.scalar(select(Settlement).where(Settlement.organizer_id == user.id,
                                                    Settlement.request_key == idempotency_key))
        if replay:
            if replay.collection_id != collection_id or replay.payout_amount != data.payout_amount:
                raise HTTPException(409, 'Request key already used with different details.')
            return overview(db, db.get(Collection, collection_id), user)
        c = organized(db, collection_id, user, lock=True)
        if db.scalar(select(Settlement.id).where(Settlement.collection_id == c.id)):
            raise HTTPException(409, 'This collection is already being sent. Check its status.')
        _, blockers, amounts, dest, policy = quote(db, c, user.id, config, configured_policy())
        if blockers:
            raise HTTPException(409, BLOCKER_TEXT[blockers[0]])
        if amounts['payout_amount'] != data.payout_amount:
            raise HTTPException(409, 'The amounts changed. Review the settlement again.')
        now = int(time.time())
        s = Settlement(collection_id=c.id, organizer_id=user.id, request_key=idempotency_key,
                       destination_id=dest.id, phone=dest.phone, method=dest.method,
                       application_hash=config.application_hash, policy=policy.model_dump(),
                       amounts=amounts, payout_amount=amounts['payout_amount'], state='SENDING',
                       payout_status='PENDING', created_at=now, updated_at=now, next_check_at=now + 30)
        db.add(s)
        c.status = 'CLOSED'
        db.add(Activity(organizer_id=user.id, collection_id=c.id,
                        message=f'{c.name} closed · sending {money(s.payout_amount)} · Sandbox'))
        try:
            db.commit()  # The reservation is durable before anything is sent.
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, 'This collection is already being sent. Check its status.')
        submit_once(sessions, request.app.state.mesomb_client, s.id)
        db.expire_all()
        return overview(db, db.get(Collection, collection_id), user)

    @routes.post('/{collection_id}/settlement/refresh')
    def refresh(collection_id: str, request: Request, user=Depends(actor), db=Depends(database)):
        c = organized(db, collection_id, user)
        s = db.scalar(select(Settlement).where(Settlement.collection_id == c.id))
        if s is None:
            raise HTTPException(404, 'Nothing has been sent for this collection.')
        if config is not None:
            reconcile(sessions, config, request.app.state.mesomb_client, s.id)  # lookup only
        db.expire_all()
        return overview(db, db.get(Collection, collection_id), user)

    return routes
