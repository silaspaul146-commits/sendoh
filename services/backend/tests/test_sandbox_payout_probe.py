import threading
from concurrent.futures import ThreadPoolExecutor
import pytest
from sqlalchemy import select
from test_mesomb_lifecycle import client
from app.payout_probe import SandboxPayoutProbe, safe_error, evidence
PATH='/api/v1/internal/sandbox-payout'
TOKEN='a'*64
HEADERS={'X-Sendoh-Diagnostic-Token':TOKEN}
BODY={'confirm':'RUN_SANDBOX_PAYOUT'}
class Provider:
    def __init__(self):
        self.calls=[]; self.lookups=[]; self.fail=False; self.rows=[]
    def deposit(self,**kwargs):
        self.calls.append(kwargs)
        if self.fail: raise TimeoutError('secret-account-data')
        return {'status':'SUCCESS'}
    def lookup(self,reference):
        self.lookups.append(reference); return self.rows
@pytest.fixture
def enabled(client,monkeypatch):
    monkeypatch.setenv('SENDOH_SANDBOX_DIAGNOSTIC_TOKEN',TOKEN)
    client.app.state.mesomb_client=Provider()
    return client

def test_access_and_body(enabled):
    assert enabled.post(PATH,json=BODY).status_code==403
    assert enabled.post(PATH,headers={'X-Sendoh-Diagnostic-Token':'wrong'},json=BODY).status_code==403
    assert enabled.post(PATH,headers=HEADERS,json={}).status_code==422
    assert enabled.post(PATH,headers=HEADERS,json=BODY|{'amount':2000}).status_code==422
    assert not enabled.app.state.mesomb_client.calls

@pytest.mark.parametrize('name,value',[('SENDOH_SANDBOX_DIAGNOSTIC_TOKEN',''),('SENDOH_SANDBOX_DIAGNOSTIC_TOKEN','short'),('SENDOH_MESOMB_MODE','live'),('MESOMB_SANDBOX_CONFIRMED','0')])
def test_disabled(enabled,monkeypatch,name,value):
    monkeypatch.setenv(name,value)
    assert enabled.post(PATH,headers=HEADERS,json=BODY).status_code==404
    assert not enabled.app.state.mesomb_client.calls

@pytest.mark.parametrize('failure',[False,True])
def test_persist_before_dispatch_and_no_repeat(enabled,failure):
    api=enabled.app.state.mesomb_client; api.fail=failure
    original=api.deposit
    def deposit(**kwargs):
        with enabled.app.state.sessions() as db:
            p=db.scalar(select(SandboxPayoutProbe))
            assert p.reference==kwargs['external_id']
            assert p.submission_result=='RESERVED_OUTCOME_UNKNOWN'
        return original(**kwargs)
    api.deposit=deposit
    first=enabled.post(PATH,headers=HEADERS,json=BODY)
    assert first.status_code==200
    for _ in range(3):
        assert enabled.post(PATH,headers=HEADERS,json=BODY).json()['reference']==first.json()['reference']
    assert len(api.calls)==1
    assert api.calls[0]['amount']==1000 and api.calls[0]['receiver']=='600000001'
    assert first.json()['delivery_confirmed'] is False
    assert 'secret-account-data' not in first.text
    assert enabled.get(PATH,headers=HEADERS).status_code==200

def test_refresh_only_reads_bounded_evidence(enabled):
    api=enabled.app.state.mesomb_client
    enabled.post(PATH,headers=HEADERS,json=BODY)
    api.rows=[dict(status='SUCCESS',type='DEPOSIT',amount=1000,fees=10,trxamount=1010,country='CM',currency='XAF',service='MTN',b_party='+237600000001',secret='hidden')]
    result=enabled.post(PATH+'/refresh',headers=HEADERS).json()
    assert result['lookup_result']=='EVIDENCE_RETRIEVED'
    assert result['provider_evidence']['receiver_matches'] is True
    assert result['provider_evidence']['amounts']=={'amount':'1000','fees':'10','trxamount':'1010'}
    assert result['delivery_confirmed'] is False and 'hidden' not in str(result)
    enabled.post(PATH+'/refresh',headers=HEADERS)
    assert len(api.calls)==1 and len(api.lookups)==1

def test_crashed_reservation_never_redispatched(enabled):
    with enabled.app.state.sessions() as db:
        db.add(SandboxPayoutProbe(application_hash=enabled.app.state.mesomb_config.application_hash,reference='reserved',created_at=1,updated_at=1,next_check_at=0,lease_until=0,submission_result='RESERVED_OUTCOME_UNKNOWN',lookup_result='NOT_CHECKED'))
        db.commit()
    assert enabled.post(PATH,headers=HEADERS,json=BODY).json()['reference']=='reserved'
    assert not enabled.app.state.mesomb_client.calls
    assert enabled.post(PATH+'/refresh',headers=HEADERS).json()['lookup_result']=='NO_MATCH_YET'

def test_concurrent_create_one_dispatch(enabled):
    api=enabled.app.state.mesomb_client; original=api.deposit
    entered=threading.Event(); release=threading.Event()
    def blocked(**kwargs):
        entered.set(); assert release.wait(5)
        return original(**kwargs)
    api.deposit=blocked
    with ThreadPoolExecutor(max_workers=2) as pool:
        first=pool.submit(enabled.post,PATH,headers=HEADERS,json=BODY)
        assert entered.wait(5)
        try:
            second=enabled.post(PATH,headers=HEADERS,json=BODY)
            assert second.status_code==200
            assert second.json()['submission_result']=='RESERVED_OUTCOME_UNKNOWN'
        finally: release.set()
        assert first.result().json()['reference']==second.json()['reference']
    assert len(api.calls)==1

def test_errors_do_not_echo_payload():
    assert safe_error(Exception('secret'))=='UNRESOLVED_ERROR'
    assert safe_error(Exception('HTTP_STATUS:400'))=='HTTP_STATUS:400'
    assert evidence([{},{}])=={'matches':2}
    assert evidence([{'status':'password=abc'}])['provider_status']=='UNKNOWN'
