from test_mesomb_lifecycle import client, setup, create
from test_collections import headers
from app.models import ProviderPayment


def test_guest_provider_history_scopes_collection_and_identity(client):
    c, token = setup(client)
    pid = create(client, c).json()['id']
    path = '/api/v1/me/provider-payments?payer_only=true&collection_token=' + token
    assert [p['id'] for p in client.get(path, headers=headers('bob')).json()['items']] == [pid]
    assert client.get(path, headers=headers('alice')).json()['items'] == []
    assert client.get(path, headers=headers('eve')).json()['items'] == []
    assert client.get(path + '&before=' + pid, headers=headers('eve')).status_code == 404
    assert client.get(path + '&before=' + pid, headers=headers('bob')).json()['items'] == []
    assert client.get(path.replace(token, 'unknown'), headers=headers('bob')).status_code == 404


def test_guest_provider_history_cursor_handles_same_timestamp(client):
    c, token = setup(client)
    pid = create(client, c).json()['id']
    with client.app.state.sessions() as db:
        first = db.get(ProviderPayment, pid)
        for i in range(101):
            db.add(ProviderPayment(id=f'page-{i:04d}', collection_id=first.collection_id,
                participant_id=first.participant_id,payer_id=first.payer_id,
                beneficiary_id=first.beneficiary_id,request_key=f'page-key-{i}',
                fingerprint='test',application_hash=first.application_hash,
                amount=1000,method='MTN',payer_phone='670000000',
                status='FAILED',created_at=first.created_at,updated_at=first.updated_at,
                next_check_at=0))
        db.commit()
    path='/api/v1/me/provider-payments?payer_only=true&collection_token='+token
    first=client.get(path,headers=headers('bob')).json()
    second=client.get(path+'&before='+first['next_cursor'],headers=headers('bob')).json()
    ids=[p['id'] for p in first['items']+second['items']]
    assert len(ids)==len(set(ids))==102
    assert second['next_cursor'] is None
