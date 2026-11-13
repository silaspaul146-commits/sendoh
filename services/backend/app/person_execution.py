"""Sandbox two-leg payment execution; committed dispatch reservations are final.

A missing/uncertain provider result always means lookup, never repeat submission.
This increment verifies only zero-fee DEPOSIT evidence. Other payout contracts
remain reviewable rather than being interpreted as successful delivery.
"""
import time
import uuid
from decimal import Decimal, InvalidOperation

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError

from .models import (PersonExecution, PersonPaymentLeg, PersonOrder, PersonQuote,
    ReceivingDestination, User, MoneyRequest, Notification, PushDevice, PushDelivery)
from .providers.mesomb import validate_transaction, collection_amounts, local_phone, ReconciliationRequired, payment_state
from .provider_claims import claim
from .person_execution_state import enabled, request_execution
from .receiving import current_destination, destination_current, identity_phone
from .fee_quotes import configured_policy


def delivery_evidence(t, leg):
    if not isinstance(t, dict):
        raise ReconciliationRequired('INVALID_PAYOUT_EVIDENCE')
    try:
        amount, fee, gross = (Decimal(str(t[k])) for k in ('amount', 'fees', 'trxamount'))
        valid = (all(x.is_finite() for x in (amount, fee, gross))
            and amount == gross == leg.amount and fee == 0
            and t.get('type') == 'DEPOSIT' and t.get('country') == 'CM'
            and t.get('currency') == 'XAF' and t.get('service') == leg.method
            and local_phone(t.get('b_party')) == leg.phone
            and isinstance(t.get('pk'), str) and 0 < len(t['pk']) <= 120
            and (leg.provider_id is None or leg.provider_id == t['pk']))
    except (KeyError, ValueError, TypeError, InvalidOperation):
        valid = False
    if not valid:
        raise ReconciliationRequired('PAYOUT_EVIDENCE_UNVERIFIED')
    return payment_state(t.get('status')), amount, fee


def emit_state(db, e, order):
    # Durable in-app/push outbox, committed with the business transition.
    now = int(time.time())
    recipients = [order.payer_id]
    if e.state == 'SUCCEEDED':
        recipients.append(order.beneficiary_id)
    for uid in recipients:
        kind = 'PERSON_RECEIVED' if uid == order.beneficiary_id else {
            'SUCCEEDED':'PERSON_DELIVERED', 'FAILED':'PERSON_FAILED',
            'REVIEW':'PERSON_REVIEW'}.get(e.state)
        if kind is None:
            continue
        key = f'person:{order.id}:{e.state}:{uid}'
        if db.scalar(select(Notification.id).where(Notification.event_key == key)):
            continue
        n = Notification(user_id=uid, order_id=order.id, request_id=order.request_id,
            kind=kind, event_key=key, created_at=now)
        db.add(n)
        db.flush()
        for device in db.scalars(select(PushDevice).where(PushDevice.user_id == uid,
                PushDevice.active == 1, PushDevice.expires_at > now)):
            db.add(PushDelivery(notification_id=n.id, device_id=device.id,
                token_hash=device.token_hash, family_id=device.family_id, due_at=now))


def execution_view(db, order_id):
    e = db.get(PersonExecution, order_id)
    if e is None:
        return None
    legs = db.scalars(select(PersonPaymentLeg).where(PersonPaymentLeg.order_id == order_id)).all()
    by_kind = {l.kind:l for l in legs}
    return dict(state=e.state, review_reason=e.reason,
        collection_status=by_kind['COLLECT'].status,
        delivery_status=by_kind['DELIVER'].status if 'DELIVER' in by_kind else 'NOT_STARTED',
        collection_reference=by_kind['COLLECT'].id,
        delivery_reference=by_kind['DELIVER'].id if 'DELIVER' in by_kind else None,
        recipient_delivery_confirmed=e.state == 'SUCCEEDED',
        updated_at=e.updated_at)


def hold_review(db, e, reason):
    # If a provider contradicts a previously terminal failed charge after the
    # payer started a replacement, freeze the replacement too. Keep the old
    # failed row out of the unique active-obligation slot.
    other = request_execution(db, e.request_id) if e.state == 'FAILED' and e.request_id else None
    e.reason = reason
    if other and other.order_id != e.order_id:
        other.state, other.reason = 'REVIEW', 'EARLIER_PAYMENT_OUTCOME_CONFLICT'
        other.updated_at = int(time.time())
        emit_state(db, other, db.get(PersonOrder, other.order_id))
    else:
        e.state = 'REVIEW'


def submit_once(sessions, api, leg_id):
    # Only the process that just committed this leg may call this function.
    # Recovery workers NEVER call it for a leg that already exists.
    with sessions() as db:
        leg = db.get(PersonPaymentLeg, leg_id)
        args = dict(external_id=leg.id, amount=leg.amount, service=leg.method)
        kind, phone = leg.kind, leg.phone
    try:
        if kind == 'COLLECT':
            api.collect(**args, payer=phone, fees_included=True)
        else:
            api.deposit(**args, receiver=phone)
    except Exception:
        with sessions() as db:
            db.execute(update(PersonPaymentLeg).where(PersonPaymentLeg.id == leg_id,
                PersonPaymentLeg.status == 'PENDING').values(review_reason='SUBMISSION_UNCERTAIN'))
            db.commit()


def reconcile_leg(sessions, config, api, leg_id):
    owner, now = str(uuid.uuid4()), int(time.time())
    with sessions() as db:
        changed = db.execute(update(PersonPaymentLeg).where(PersonPaymentLeg.id == leg_id,
            PersonPaymentLeg.application_hash == config.application_hash,
            PersonPaymentLeg.lease_until <= now, PersonPaymentLeg.next_check_at <= now)
            .values(lease_owner=owner, lease_until=now+90))
        db.commit()
        if changed.rowcount != 1:
            return
        leg = db.get(PersonPaymentLeg, leg_id)
        kind = leg.kind
        desired = net = fee = transaction = None
        reason = None
        try:
            rows = api.lookup(leg.id)
            if len(rows) != 1:
                reason = 'NO_MATCH_YET' if not rows else 'MULTIPLE_MATCHES'
            else:
                transaction = rows[0]
                if kind == 'COLLECT':
                    desired = validate_transaction(transaction, amount=leg.amount,
                        service=leg.method, payer=leg.phone, provider_id=leg.provider_id)
                    if desired == 'SUCCEEDED':
                        evidence = collection_amounts(transaction, amount=leg.amount)
                        if evidence is None:
                            raise ReconciliationRequired('ACCOUNTING_MISSING')
                        _, fee, net = evidence
                else:
                    desired, net, fee = delivery_evidence(transaction, leg)
        except Exception:
            reason = 'PROVIDER_EVIDENCE_UNVERIFIED'
    with sessions() as db:
        # Lock execution before leg consistently with dispatch_delivery.
        e = db.scalar(select(PersonExecution).where(PersonExecution.order_id == leg.order_id).with_for_update())
        row = db.scalar(select(PersonPaymentLeg).where(PersonPaymentLeg.id == leg_id,
            PersonPaymentLeg.lease_owner == owner).with_for_update())
        if row is None:
            return
        order = db.get(PersonOrder, row.order_id)
        q = db.get(PersonQuote, order.quote_id)
        row.attempts += 1
        if reason is None and desired is not None:
            if not claim(db, config.application_hash, transaction['pk'], row.id):
                reason = 'DUPLICATE_PROVIDER_TRANSACTION'
            elif row.status != 'PENDING' and desired not in (row.status, 'REFUNDED'):
                reason = 'CONFLICTING_PROVIDER_OUTCOME'
            elif row.net is not None and net is not None and (row.net != net or row.fee != fee):
                reason = 'CONFLICTING_PROVIDER_ACCOUNTING'
        if reason is None and desired is not None:
            row.provider_id = transaction['pk']
            row.status = desired
            if net is not None:
                row.net, row.fee = net, fee
            if desired == 'REFUNDED':
                hold_review(db, e, 'PROVIDER_REFUND_REQUIRES_REVIEW')
            elif kind == 'COLLECT' and desired == 'FAILED':
                e.state, e.reason = 'FAILED', None
                order.status = 'CANCELLED'
            elif kind == 'COLLECT' and desired == 'SUCCEEDED' and (e.state == 'COLLECTING'
                    or (e.state == 'REVIEW' and e.reason in ('COLLECT:PROVIDER_EVIDENCE_UNVERIFIED','COLLECT:MULTIPLE_MATCHES'))):
                if net < Decimal(q.amounts['expected_collection_net']):
                    e.state, e.reason = 'REVIEW', 'CONFIRMED_NET_BELOW_QUOTE'
                else:
                    e.state, e.reason = 'FUNDED', None
            elif kind == 'DELIVER' and desired == 'FAILED':
                e.state, e.reason = 'REVIEW', 'DELIVERY_FAILED_FUNDS_RETAINED'
            elif kind == 'DELIVER' and desired == 'SUCCEEDED' and (e.state == 'DELIVERING'
                    or (e.state == 'REVIEW' and e.reason in ('DELIVER:PROVIDER_EVIDENCE_UNVERIFIED','DELIVER:MULTIPLE_MATCHES'))):
                e.state, e.reason = 'SUCCEEDED', None
        elif reason not in ('NO_MATCH_YET', None):
            hold_review(db, e, kind + ':' + reason)
        row.review_reason = reason
        e.updated_at = int(time.time())
        row.next_check_at = e.updated_at + (min(3600, 15*2**min(row.attempts,8)) if row.status == 'PENDING' else 86400)
        row.lease_until, row.lease_owner = 0, None
        emit_state(db, e, order)
        db.commit()


def dispatch_delivery(sessions, config, api, order_id):
    if not enabled(config):
        return
    with sessions() as db:
        initial_order = db.get(PersonOrder, order_id)
        if initial_order is None:
            return
        db.scalar(select(User).where(User.id == initial_order.beneficiary_id).with_for_update())
        e = db.scalar(select(PersonExecution).where(PersonExecution.order_id == order_id,
            PersonExecution.application_hash == config.application_hash).with_for_update())
        if e is None or e.state != 'FUNDED':
            return
        # CAS also serializes SQLite, before checking the unique delivery leg.
        changed = db.execute(update(PersonExecution).where(PersonExecution.order_id == order_id,
            PersonExecution.state == 'FUNDED').values(state='DELIVERING'))
        if changed.rowcount != 1:
            db.rollback()
            return
        order = db.get(PersonOrder, order_id)
        q = db.get(PersonQuote, order.quote_id)
        d = db.get(ReceivingDestination, q.destination_id)
        current = current_destination(db, order.beneficiary_id)
        funding = db.scalar(select(PersonPaymentLeg).where(PersonPaymentLeg.order_id == order_id,
            PersonPaymentLeg.kind == 'COLLECT'))
        reason = None
        if funding.status != 'SUCCEEDED' or funding.net is None or funding.net < q.amounts['expected_collection_net']:
            reason = 'FUNDING_NOT_VERIFIED'
        elif current is None or current.id != d.id or not destination_current(db, d):
            reason = 'RECEIVING_DETAILS_CHANGED_AFTER_FUNDING'
        elif d.phone not in config.test_phones:
            reason = 'SANDBOX_RECEIVER_NOT_ALLOWED'
        elif q.amounts['delivery_fee'] != 0:
            reason = 'PAYOUT_FEE_CONTRACT_NOT_VERIFIED'
        if reason:
            e.state, e.reason = 'REVIEW', reason
            e.updated_at = int(time.time())
            emit_state(db, e, order)
            db.commit()
            return
        leg = PersonPaymentLeg(order_id=order_id, kind='DELIVER', amount=q.amounts['recipient_amount'],
            phone=d.phone, method=d.method, application_hash=config.application_hash,
            created_at=int(time.time()), next_check_at=int(time.time())+30)
        db.add(leg)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            return
        leg_id = leg.id
    submit_once(sessions, api, leg_id)


def run_due(sessions, config, api, order_id=None):
    with sessions() as db:
        query = select(PersonPaymentLeg.id).where(PersonPaymentLeg.application_hash == config.application_hash,
            PersonPaymentLeg.next_check_at <= int(time.time()), PersonPaymentLeg.lease_until <= int(time.time()))
        if order_id:
            query = query.where(PersonPaymentLeg.order_id == order_id)
        ids = list(db.scalars(query.order_by(PersonPaymentLeg.next_check_at).limit(20)))
    for id in ids:
        reconcile_leg(sessions, config, api, id)
    with sessions() as db:
        query = select(PersonExecution.order_id).where(PersonExecution.application_hash == config.application_hash,
            PersonExecution.state == 'FUNDED')
        if order_id:
            query = query.where(PersonExecution.order_id == order_id)
        funded = list(db.scalars(query.limit(20)))
    for id in funded:
        dispatch_delivery(sessions, config, api, id)


def router(database, actor, sessions, config):
    routes = APIRouter(prefix='/api/v1/person-payments/orders')

    @routes.post('/{id}/execute')
    def execute(id: str, request: Request, user=Depends(actor), db=Depends(database)):
        from .person_orders import order_view
        order = db.get(PersonOrder, id)
        if order is None or order.payer_id != user.id:
            raise HTTPException(404, 'Payment order not found.')
        if db.get(PersonExecution, id):
            return order_view(db, order, config)
        if not enabled(config):
            raise HTTPException(503, 'Person payment execution is not enabled.')
        q = db.get(PersonQuote, order.quote_id)
        list(db.scalars(select(User).where(User.id.in_([user.id,order.beneficiary_id]))
            .order_by(User.id).with_for_update()))
        if db.get(PersonExecution, id):
            return order_view(db, order, config)
        r = None
        if order.request_id:
            r = db.scalar(select(MoneyRequest).where(MoneyRequest.id == order.request_id).with_for_update())
            if r.status != 'PENDING' or r.recipient_id != user.id or r.requester_id != order.beneficiary_id:
                raise HTTPException(409, 'Request is no longer payable.')
            if request_execution(db, r.id):
                raise HTTPException(409, 'This request already has a payment in progress.')
        now = int(time.time())
        policy = configured_policy()
        d = current_destination(db, order.beneficiary_id)
        if (order.status != 'READY' or order.expires_at <= now or q.expires_at <= now
                or (r and r.expires_at is not None and r.expires_at <= now)):
            raise HTTPException(409, 'Payment preparation expired or was cancelled.')
        if policy is None or policy.fingerprint != q.policy_hash or q.application_hash != config.application_hash:
            raise HTTPException(409, 'Payment terms changed. Review a new quote.')
        if identity_phone(db, user.id) != q.payer_phone or not destination_current(db,d) or d.id != q.destination_id:
            raise HTTPException(409, 'Payment identities changed. Review a new quote.')
        if q.payer_phone not in config.test_phones or d.phone not in config.test_phones:
            raise HTTPException(409, 'Use authorized sandbox payment identities.')
        if q.amounts['delivery_fee'] != 0:
            raise HTTPException(409, 'This payout fee contract is not verified. No charge was submitted.')
        # Lock request and order with conditional writes before durable dispatch.
        if r:
            changed = db.execute(update(MoneyRequest).where(MoneyRequest.id == r.id,
                MoneyRequest.status == 'PENDING',
                (MoneyRequest.expires_at.is_(None) | (MoneyRequest.expires_at > now))).values(status='PENDING'))
            if changed.rowcount != 1:
                raise HTTPException(409, 'Request changed.')
        changed = db.execute(update(PersonOrder).where(PersonOrder.id == id,
            PersonOrder.status == 'READY', PersonOrder.expires_at > now).values(status='READY'))
        if changed.rowcount != 1:
            raise HTTPException(409, 'Order changed.')
        e = PersonExecution(order_id=id, request_id=order.request_id, application_hash=config.application_hash,
            created_at=now, updated_at=now)
        leg = PersonPaymentLeg(order_id=id, application_hash=config.application_hash, kind='COLLECT',
            amount=q.amounts['total_debit'], phone=q.payer_phone, method=q.payer_method,
            created_at=now, next_check_at=now+30)
        try:
            db.add(e)
            db.flush()
            db.add(leg)
            db.commit()
        except IntegrityError:
            db.rollback()
            if db.get(PersonExecution, id):
                return order_view(db, db.get(PersonOrder,id), config)
            raise HTTPException(409, 'Payment already in progress. Resume the saved order.') from None
        submit_once(sessions, request.app.state.mesomb_client, leg.id)
        db.expire_all()
        return order_view(db, db.get(PersonOrder,id), config)

    @routes.post('/{id}/refresh')
    def refresh(id: str, request: Request, user=Depends(actor), db=Depends(database)):
        from .person_orders import order_view
        order = db.get(PersonOrder,id)
        if order is None or user.id not in (order.payer_id, order.beneficiary_id):
            raise HTTPException(404, 'Payment order not found.')
        if config:
            run_due(sessions, config, request.app.state.mesomb_client, id)
        db.expire_all()
        return order_view(db, db.get(PersonOrder,id), config)

    return routes
