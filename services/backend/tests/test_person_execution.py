import json
import time
from decimal import Decimal
import pytest
from sqlalchemy import select, update, func

from app.models import (PersonExecution, PersonPaymentLeg, PersonOrder, PersonQuote,
    Notification, ProviderReferenceClaim)
from app.person_execution import run_due, reconcile_leg
from test_person_orders import prepared, POLICY, quote, accept
from test_mesomb_lifecycle import client
from test_collections import headers


class Provider:
    def __init__(self):
        self.calls = []
        self.rows = {}
        self.timeout = False
        self.empty = False
        self.underfunded = False
        self.delivery_failed = False
    def collect(self, **data):
        self.calls.append(('collect',data))
        fee = (data['amount']*200+9999)//10000
        self.rows[data['external_id']] = dict(pk='provider-'+data['external_id'],
            status='SUCCESS', type='PAYMENT', amount=data['amount']-fee,
            trxamount=data['amount'], fees=fee, country='CM', currency='XAF',
            service=data['service'], b_party=data['payer'])
        if self.underfunded:
            self.rows[data['external_id']]['fees'] += 100
            self.rows[data['external_id']]['amount'] -= 100
        if self.timeout:
            raise TimeoutError()
        return {'success':True}
    def deposit(self, **data):
        self.calls.append(('deposit',data))
        self.rows[data['external_id']] = dict(pk='provider-'+data['external_id'],
            status='FAILED' if self.delivery_failed else 'SUCCESS', type='DEPOSIT',
            amount=data['amount'], trxamount=data['amount'], fees=0, country='CM', currency='XAF',
            service=data['service'], b_party=data['receiver'])
        if self.timeout:
            raise TimeoutError()
        return {'success':True}
    def lookup(self, reference):
        return [] if self.empty or reference not in self.rows else [self.rows[reference]]


@pytest.fixture
def flow(prepared, monkeypatch):
    c,r = prepared
    monkeypatch.setenv('SENDOH_SANDBOX_PERSON_PAYMENTS','1')
    monkeypatch.setenv('SENDOH_SANDBOX_PERSON_FEE_POLICY',json.dumps({**POLICY,'payout_bps':0}))
    # Replace the fixture's whitelist with the authenticated test identities.
    config=c.app.state.mesomb_config
    object.__setattr__(config,'test_phones',frozenset(('682248238','690000001')))
    c.app.state.mesomb_client=Provider()
    q=quote(c,r['id']).json()
    o=accept(c,q).json()
    return c,r,o


def start(c,o,who='bob'):
    return c.post('/api/v1/person-payments/orders/'+o['id']+'/execute',headers=headers(who))


def sweep(c):
    with c.app.state.sessions() as db:
        db.execute(update(PersonPaymentLeg).values(next_check_at=0,lease_until=0))
        db.commit()
    run_due(c.app.state.sessions,c.app.state.mesomb_config,c.app.state.mesomb_client)


def detail(c,o):
    return c.get('/api/v1/person-payments/orders/'+o['id'],headers=headers('bob')).json()


def test_request_paid_only_after_verified_delivery_and_events_once(flow):
    c,r,o=flow
    response=start(c,o)
    assert response.status_code==200,response.text
    assert response.json()['status']=='COLLECTING'
    assert start(c,o).json()['id']==o['id']
    assert len(c.app.state.mesomb_client.calls)==1
    assert c.get('/api/v1/money-requests/'+r['id'],headers=headers('bob')).json()['status']=='PROCESSING'
    sweep(c)
    assert detail(c,o)['status']=='DELIVERING'
    assert detail(c,o)['receipt_available'] is False
    sweep(c)
    assert detail(c,o)['status']=='SUCCEEDED'
    assert detail(c,o)['receipt_available'] is True
    assert c.get('/api/v1/money-requests/'+r['id'],headers=headers()).json()['status']=='PAID'
    sweep(c)
    assert len(c.app.state.mesomb_client.calls)==2
    with c.app.state.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Notification).where(Notification.order_id==o['id']))==2
    inbox=c.get('/api/v1/me/notifications',headers=headers()).json()
    assert any(n['title']=='bob sent you 3000 FCFA' for n in inbox['items'])


def test_ambiguous_collect_and_delivery_never_resubmit(flow):
    c,r,o=flow
    c.app.state.mesomb_client.timeout=True
    start(c,o)
    c.app.state.mesomb_client.empty=True
    for _ in range(3):
        start(c,o);sweep(c)
    assert len(c.app.state.mesomb_client.calls)==1
    assert detail(c,o)['status']=='COLLECTING'
    c.app.state.mesomb_client.empty=False
    sweep(c);sweep(c)
    assert len(c.app.state.mesomb_client.calls)==2
    assert detail(c,o)['status']=='SUCCEEDED'


def test_no_payout_when_confirmed_net_cannot_cover_principal_and_fees(flow):
    c,r,o=flow
    c.app.state.mesomb_client.underfunded=True
    start(c,o);sweep(c)
    assert len(c.app.state.mesomb_client.calls)==1
    assert detail(c,o)['status']=='REVIEW'
    assert detail(c,o)['execution']['review_reason']=='CONFIRMED_NET_BELOW_QUOTE'


def test_delivery_failure_is_retained_obligation_not_failed_charge(flow):
    c,r,o=flow
    c.app.state.mesomb_client.delivery_failed=True
    start(c,o);sweep(c);sweep(c)
    assert detail(c,o)['status']=='REVIEW'
    assert detail(c,o)['collection_status']=='SUCCEEDED'
    assert detail(c,o)['delivery_status']=='FAILED'
    assert detail(c,o)['receipt_available'] is False
    assert c.get('/api/v1/money-requests/'+r['id'],headers=headers()).json()['status']=='PAYMENT_REVIEW'
    assert quote(c,r['id']).status_code==409
    assert len(c.app.state.mesomb_client.calls)==2


def test_no_cancellation_or_second_order_after_dispatch(flow):
    c,r,o=flow
    start(c,o)
    assert c.post('/api/v1/person-payments/orders/'+o['id']+'/cancel',headers=headers('bob')).status_code==409
    assert c.post('/api/v1/money-requests/'+r['id']+'/respond',headers=headers(),json={'action':'CANCEL'}).status_code==409
    assert c.post('/api/v1/money-requests/'+r['id']+'/respond',headers=headers('bob'),json={'action':'DECLINE'}).status_code==409
    assert quote(c,r['id']).status_code==409
    with c.app.state.sessions() as db:
        db.get(PersonOrder,o['id']).expires_at=1
        db.commit()
    assert start(c,o).json()['status']=='COLLECTING'


def test_expired_or_disabled_cannot_dispatch(flow,monkeypatch):
    c,r,o=flow
    monkeypatch.delenv('SENDOH_SANDBOX_PERSON_PAYMENTS')
    assert start(c,o).status_code==503
    monkeypatch.setenv('SENDOH_SANDBOX_PERSON_PAYMENTS','1')
    with c.app.state.sessions() as db:
        db.get(PersonOrder,o['id']).expires_at=1;db.commit()
    assert start(c,o).status_code==409
    assert c.app.state.mesomb_client.calls==[]


def test_provider_identity_cannot_credit_two_references(flow):
    c,r,o=flow
    start(c,o)
    ref=c.app.state.mesomb_client.calls[0][1]['external_id']
    with c.app.state.sessions() as db:
        db.add(ProviderReferenceClaim(application_hash=c.app.state.mesomb_config.application_hash,
            provider_id='provider-'+ref,sendoh_reference='another-reference'))
        db.commit()
    sweep(c)
    assert detail(c,o)['status']=='REVIEW'
    assert len(c.app.state.mesomb_client.calls)==1


def test_receiver_mismatch_never_produces_receipt(flow):
    c,r,o=flow
    start(c,o);sweep(c)
    ref=c.app.state.mesomb_client.calls[-1][1]['external_id']
    c.app.state.mesomb_client.rows[ref]['b_party']='600000099'
    sweep(c)
    assert detail(c,o)['status']=='REVIEW'
    assert detail(c,o)['receipt_available'] is False


def test_confirmed_collection_failure_releases_request(flow):
    c,r,o=flow
    start(c,o)
    ref=c.app.state.mesomb_client.calls[0][1]['external_id']
    c.app.state.mesomb_client.rows[ref]['status']='FAILED'
    sweep(c)
    assert detail(c,o)['status']=='FAILED'
    assert c.get('/api/v1/money-requests/'+r['id'],headers=headers()).json()['status']=='PENDING'
    assert quote(c,r['id']).status_code==201


def test_wrong_actor_cannot_execute(flow):
    c,r,o=flow
    assert start(c,o,'alice').status_code==404
    assert c.app.state.mesomb_client.calls==[]


def test_crash_after_collection_reservation_never_reissues_charge(flow,monkeypatch):
    c,r,o=flow
    def crash(*args):
        raise RuntimeError('process terminated after commit')
    monkeypatch.setattr('app.person_execution.submit_once',crash)
    with pytest.raises(RuntimeError):
        start(c,o)
    monkeypatch.undo()
    for _ in range(2):
        assert start(c,o).json()['status']=='COLLECTING'
        sweep(c)
    assert c.app.state.mesomb_client.calls==[]


def test_recovery_of_delivery_evidence_does_not_reissue_deposit(flow):
    c,r,o=flow
    start(c,o);sweep(c)
    ref=c.app.state.mesomb_client.calls[-1][1]['external_id']
    row=c.app.state.mesomb_client.rows[ref]
    row['amount']-=1
    sweep(c)
    assert detail(c,o)['status']=='REVIEW'
    row['amount']+=1
    sweep(c)
    assert detail(c,o)['status']=='SUCCEEDED'
    assert len(c.app.state.mesomb_client.calls)==2


def test_receiver_change_after_funding_stops_delivery(flow):
    c,r,o=flow
    start(c,o)
    with c.app.state.sessions() as db:
        leg=db.scalar(select(PersonPaymentLeg).where(PersonPaymentLeg.order_id==o['id']))
        leg.next_check_at=0;db.commit();ref=leg.id
    reconcile_leg(c.app.state.sessions,c.app.state.mesomb_config,c.app.state.mesomb_client,ref)
    from test_receiving import save
    assert save(c,method='ORANGE',version=1).status_code==200
    sweep(c)
    assert detail(c,o)['status']=='REVIEW'
    assert len(c.app.state.mesomb_client.calls)==1


def test_post_delivery_refund_revokes_receipt_and_requires_review(flow):
    c,r,o=flow
    start(c,o);sweep(c);sweep(c)
    ref=c.app.state.mesomb_client.calls[0][1]['external_id']
    c.app.state.mesomb_client.rows[ref]['status']='REFUNDED'
    sweep(c)
    assert detail(c,o)['status']=='REVIEW'
    assert detail(c,o)['receipt_available'] is False


def test_recipient_can_read_executed_order_but_not_cancel_it(flow):
    c,r,o=flow
    assert c.get('/api/v1/person-payments/orders/'+o['id'],headers=headers()).status_code==404
    start(c,o)
    assert c.get('/api/v1/person-payments/orders/'+o['id'],headers=headers()).status_code==200
    assert c.post('/api/v1/person-payments/orders/'+o['id']+'/cancel',headers=headers()).status_code==403


def test_contradiction_after_failed_charge_holds_replacement(flow):
    c,r,o=flow
    start(c,o)
    ref=c.app.state.mesomb_client.calls[0][1]['external_id']
    c.app.state.mesomb_client.rows[ref]['status']='FAILED'
    sweep(c)
    newer=accept(c,quote(c,r['id']).json(),'replacement-order-key').json()
    assert start(c,newer).status_code==200
    c.app.state.mesomb_client.rows[ref]['status']='SUCCESS'
    sweep(c)
    assert detail(c,newer)['status']=='REVIEW'
    assert not any(kind=='deposit' for kind,_ in c.app.state.mesomb_client.calls)


def test_payment_push_contains_specific_delivery_message(flow):
    c,r,o=flow
    from test_notifications import dispatch
    from app.models import PushDevice, User
    import hashlib
    # Seed an already registered device: this fixture intentionally has no
    # configured Firebase sender, and registration is covered separately.
    with c.app.state.sessions() as db:
        uid=db.scalar(select(User.id).where(User.username=='bob'))
        token='test-device-token-1234567890'
        db.add(PushDevice(user_id=uid,family_id='dev:'+uid,token=token,
            token_hash=hashlib.sha256(token.encode()).hexdigest(),platform='android',
            updated_at=int(time.time()),expires_at=int(time.time())+3600))
        db.commit()
    class Sender:
        def __init__(self): self.bodies=[]
        def send(self, token, notification_id, *, body=None): self.bodies.append(body)
    start(c,o);sweep(c);sweep(c)
    sender=Sender()
    for _ in range(3): dispatch(c,sender)
    assert sender.bodies == ['3000 FCFA delivered to alice']
