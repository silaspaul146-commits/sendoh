import hashlib
import hmac
import json
import time
from dataclasses import replace
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select, func
from app.main import create_app
from app.models import Base, User, ProviderPayment, ProviderPaymentEvent, MeSombWebhook
from app.mesomb_payments import reconcile, run_due
from app.providers.mesomb import ReconciliationRequired
from test_collections import headers
from test_invitations import collection, bind_phone


class FakeProvider:
    def __init__(self):
        self.calls = []
        self.status = 'SUCCESS'
        self.timeout = False
        self.mismatch = False
        self.empty = False
    def collect(self, **kwargs):
        self.calls.append(kwargs)
        if self.timeout:
            raise ReconciliationRequired('timeout')
        return {'success': True, 'status': 'SUCCESS'}
    def lookup(self, external_id):
        if self.empty:
            return []
        call = next(c for c in self.calls if c['external_id'] == external_id)
        return [dict(pk='provider-'+external_id, status=self.status, type='COLLECT',
                     amount=call['amount'] + int(self.mismatch), service=call['service'],
                     b_party=call['payer'], country='CM', currency='XAF')]


@pytest.fixture
def client(monkeypatch, tmp_path):
    monkeypatch.setenv('SENDOH_MESOMB_MODE','sandbox')
    monkeypatch.setenv('MESOMB_SANDBOX_CONFIRMED','1')
    for key in ('APPLICATION_KEY','ACCESS_KEY','SECRET_KEY','WEBHOOK_SECRET'):
        monkeypatch.setenv('MESOMB_'+key, 'sandbox-test-'+key)
    monkeypatch.setenv('MESOMB_TEST_PHONES','670000000,690000000')
    app = create_app('sqlite:///'+str(tmp_path/'payments.db'))
    Base.metadata.create_all(app.state.engine)
    with app.state.sessions() as db:
        db.add_all([User(display_name=n,username=n,token_hash=hashlib.sha256(n.encode()).hexdigest())
                    for n in ('alice','bob','eve')])
        db.commit()
    app.state.mesomb_client = FakeProvider()
    # Endpoint tests invoke the same worker function explicitly for determinism.
    yield TestClient(app)


def setup(client):
    bind_phone(client)
    c=collection(client)
    token=c['share_url'].split('/')[-1]
    assert client.post('/api/v1/me/guest-collections/'+token+'/join',headers=headers('bob'),json={}).status_code==200
    return c, token


def create(client,c,key='provider-key-001',**changes):
    body=dict(collection_id=c['id'],amount=1000,method='MTN',payer_phone='670000000')
    body.update(changes)
    return client.post('/api/v1/provider-payments',headers=headers('bob',key),json=body)


def due(client,pid):
    with client.app.state.sessions() as db:
        p=db.get(ProviderPayment,pid); p.next_check_at=0;db.commit()
    reconcile(client.app.state.sessions,client.app.state.mesomb_config,client.app.state.mesomb_client,pid)


def result(client,pid):
    return client.get('/api/v1/provider-payments/'+pid,headers=headers('bob')).json()


def test_persist_before_dispatch_and_idempotency(client):
    c,_=setup(client)
    fake=client.app.state.mesomb_client
    original=fake.collect
    def inspect(**kwargs):
        with client.app.state.sessions() as db:
            assert db.get(ProviderPayment,kwargs['external_id']).status=='PENDING'
        return original(**kwargs)
    fake.collect=inspect
    first=create(client,c); assert first.status_code==201,first.text
    pid=first.json()['id']
    assert first.json()['status']=='PENDING'  # initiation SUCCESS isn't proof
    assert create(client,c).json()['id']==pid
    assert create(client,c,amount=999).status_code==409
    assert create(client,c,key='different-key').status_code==409
    assert len(fake.calls)==1
    due(client,pid)
    assert result(client,pid)['status']=='SUCCEEDED'
    due(client,pid)
    with client.app.state.sessions() as db:
        assert db.scalar(select(func.count()).select_from(ProviderPaymentEvent))==1
    summary=client.get('/api/v1/collections/'+c['id'],headers=headers()).json()
    assert summary['sandbox_collected_amount']==1000
    assert summary['collected_amount']==summary['test_collected_amount']==0


def test_guest_token_same_identity_and_owner_access(client):
    c,token=setup(client)
    r=create(client,c,collection_id=None,collection_token=token)
    assert r.status_code==201,r.text
    pid=r.json()['id']
    assert client.get('/api/v1/provider-payments/'+pid,headers=headers('eve')).status_code==404
    assert client.get('/api/v1/provider-payments/'+pid,headers=headers()).status_code==200
    assert client.get('/api/v1/provider-payments/'+pid).status_code==401
    assert client.post('/api/v1/provider-payments/'+pid+'/simulate',headers=headers('bob'),json={'status':'SUCCEEDED'}).status_code==404


def test_timeout_missing_callback_recovery_no_recharge(client):
    c,_=setup(client);fake=client.app.state.mesomb_client;fake.timeout=True
    pid=create(client,c).json()['id']
    fake.empty=True;due(client,pid)
    assert result(client,pid)['status']=='PENDING'
    assert create(client,c).json()['id']==pid
    fake.empty=False;due(client,pid)
    assert result(client,pid)['status']=='SUCCEEDED'
    assert len(fake.calls)==1


@pytest.mark.parametrize('state',['COLLECTED','ONGOING','CANCELED','ERRORED','UNRECOGNIZED'])
def test_intermediate_results_never_credit(client,state):
    c,_=setup(client);pid=create(client,c).json()['id']
    client.app.state.mesomb_client.status=state;due(client,pid)
    assert result(client,pid)['status']=='PENDING'
    assert client.get('/api/v1/collections/'+c['id'],headers=headers()).json()['sandbox_collected_amount']==0


def test_failed_attempt_allows_new_intent(client):
    c,_=setup(client);pid=create(client,c).json()['id']
    client.app.state.mesomb_client.status='FAILED';due(client,pid)
    assert result(client,pid)['status']=='FAILED'
    assert create(client,c,key='new-intent-key').status_code==201


def test_refund_reverses_sandbox_total_without_erasing_history(client):
    c,_=setup(client);pid=create(client,c).json()['id'];due(client,pid)
    client.app.state.mesomb_client.status='REFUNDED';due(client,pid)
    assert result(client,pid)['status']=='REFUNDED'
    assert client.get('/api/v1/collections/'+c['id'],headers=headers()).json()['sandbox_collected_amount']==0
    with client.app.state.sessions() as db:
        assert db.scalar(select(func.count()).select_from(ProviderPaymentEvent))==2
    client.app.state.mesomb_client.status='SUCCESS';due(client,pid)
    assert result(client,pid)['status']=='REFUNDED'
    assert result(client,pid)['review_reason']=='CONFLICTING_PROVIDER_OUTCOME'


def test_mismatch_requires_review(client):
    c,_=setup(client);pid=create(client,c).json()['id']
    client.app.state.mesomb_client.mismatch=True;due(client,pid)
    assert result(client,pid)['status']=='PENDING'
    assert result(client,pid)['review_reason']=='PROVIDER_UNVERIFIED'


def signed(client,payload,stamp=None):
    stamp=str(stamp or int(time.time()))
    raw=json.dumps(payload).encode()
    secret=client.app.state.mesomb_config.webhook_secret
    signature=hmac.new(secret.encode(),stamp.encode()+b'.'+raw,hashlib.sha256).hexdigest()
    return raw,{'X-MeSomb-Webhook-Event-Id':payload['id'],
                'X-MeSomb-Webhook-Request-Timestamp':stamp,
                'X-MeSomb-Webhook-Signature':f't={stamp},v1={signature}'}


def test_signed_webhook_dedup_and_untrusted_payload_status(client):
    c,_=setup(client);pid=create(client,c).json()['id']
    payload={'id':'evt-001','type':'payment.transaction.success','data':{'object':{'pk':'provider-'+pid,'status':'SUCCESS'}}}
    raw,h=signed(client,payload)
    for _ in range(2):
        assert client.post('/api/v1/webhooks/mesomb',content=raw,headers=h).status_code==200
    assert result(client,pid)['status']=='PENDING'
    client.app.state.mesomb_client.status='FAILED'
    run_due(client.app.state.sessions,client.app.state.mesomb_config,client.app.state.mesomb_client)
    assert result(client,pid)['status']=='FAILED'
    with client.app.state.sessions() as db:
        assert db.scalar(select(func.count()).select_from(MeSombWebhook))==1
    assert client.post('/api/v1/webhooks/mesomb',content=raw+b' ',headers=h).status_code==400
    raw,h=signed(client,payload,int(time.time())-600)
    assert client.post('/api/v1/webhooks/mesomb',content=raw,headers=h).status_code==400


def test_test_phone_allowlist(client):
    c,_=setup(client)
    assert create(client,c,payer_phone='677123456').status_code==422
    assert not client.app.state.mesomb_client.calls


def test_application_change_does_not_reconcile_old_attempt(client):
    c,_=setup(client);pid=create(client,c).json()['id']
    with client.app.state.sessions() as db:
        p=db.get(ProviderPayment,pid);p.next_check_at=0;db.commit()
    cfg=replace(client.app.state.mesomb_config,application_hash='other')
    reconcile(client.app.state.sessions,cfg,client.app.state.mesomb_client,pid)
    assert result(client,pid)['status']=='PENDING'


def test_persisted_attempt_reconciles_with_fresh_application(client):
    c,_=setup(client);pid=create(client,c).json()['id']
    with client.app.state.sessions() as db:
        p=db.get(ProviderPayment,pid);p.next_check_at=0;db.commit()
    restarted=create_app(str(client.app.state.engine.url))
    restarted.state.mesomb_client=client.app.state.mesomb_client
    run_due(restarted.state.sessions,restarted.state.mesomb_config,restarted.state.mesomb_client)
    assert result(client,pid)['status']=='SUCCEEDED'
    assert len(client.app.state.mesomb_client.calls)==1
    restarted.state.engine.dispose()


def test_webhook_id_collision_rejected(client):
    payload={'id':'evt-fixed','type':'payment.transaction.success'}
    raw,h=signed(client,payload)
    assert client.post('/api/v1/webhooks/mesomb',content=raw,headers=h).status_code==200
    raw,h=signed(client,payload | {'type':'payment.transaction.failed'})
    assert client.post('/api/v1/webhooks/mesomb',content=raw,headers=h).status_code==409


def test_active_lease_prevents_parallel_reconciliation(client):
    c,_=setup(client);pid=create(client,c).json()['id']
    with client.app.state.sessions() as db:
        p=db.get(ProviderPayment,pid);p.next_check_at=0;p.lease_until=int(time.time())+60;p.lease_owner='other-worker';db.commit()
    run_due(client.app.state.sessions,client.app.state.mesomb_config,client.app.state.mesomb_client)
    assert result(client,pid)['status']=='PENDING'


def test_sandbox_requires_explicit_settings(client,monkeypatch):
    from app.mesomb_payments import configuration
    settings=client.app.state.settings
    monkeypatch.setenv('SENDOH_MESOMB_MODE','live')
    with pytest.raises(RuntimeError):configuration(settings)
    monkeypatch.setenv('SENDOH_MESOMB_MODE','sandbox')
    with pytest.raises(RuntimeError):configuration(replace(settings,environment='production'))
    monkeypatch.delenv('MESOMB_SANDBOX_CONFIRMED')
    with pytest.raises(RuntimeError):configuration(settings)
    monkeypatch.setenv('SENDOH_MESOMB_MODE','disabled')
    assert configuration(settings) is None
