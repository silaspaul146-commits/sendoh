from sqlalchemy.orm import Session
from sqlalchemy import select
from app.models import User
from test_collections import client, headers
from test_invitations import collection, bind_phone, invite


def test_general_link_reuses_invitation(client):
    bind_phone(client)
    c = collection(client)
    p = invite(client, c).json()
    path = '/api/v1/me/guest-collections/' + c['share_url'].split('/')[-1] + '/join'
    assert client.post(path, headers=headers('bob'), json={}).status_code == 200
    assert client.post(path, headers=headers('bob'), json={}).json()['id'] == p['id']
    rows = client.get('/api/v1/collections/' + c['id'], headers=headers()).json()['participants']
    assert len(rows) == 1 and rows[0]['invitation_state'] == 'ACCEPTED'


def test_manual_name_requires_explicit_owner_link(client):
    bind_phone(client)
    c = collection(client, mode='EXPECTED_TOTAL', expected_amount=3000,
        participants=[{'name':'bob','expected_amount':5000}])
    old = c['participants'][0]
    joined = client.post('/api/v1/me/guest-collections/' + c['share_url'].split('/')[-1] + '/join', headers=headers('bob'), json={}).json()
    assert joined['id'] != old['id']
    path = f"/api/v1/collections/{c['id']}/participants/{old['id']}/link/{joined['id']}"
    assert client.post(path, headers=headers('bob'), json={}).status_code == 404
    result = client.post(path, headers=headers(), json={})
    assert result.status_code == 200, result.text
    assert result.json()['expected_amount'] == 5000
    data = client.get('/api/v1/collections/' + c['id'], headers=headers()).json()
    assert len(data['participants']) == 1 and data['collected_amount'] == 0


def test_join_needs_phone_and_does_not_reactivate_decline(client):
    c = collection(client)
    path = '/api/v1/me/guest-collections/' + c['share_url'].split('/')[-1] + '/join'
    assert client.post(path, headers=headers('bob'), json={}).status_code == 403
    bind_phone(client)
    p = invite(client,c).json()
    client.post(f"/api/v1/me/invitations/{p['id']}/respond", headers=headers('bob'), json={'decision':'decline'})
    assert client.post(path, headers=headers('bob'), json={}).status_code == 409


def test_member_avatar_not_public(client):
    bind_phone(client)
    c = collection(client)
    token = c['share_url'].split('/')[-1]
    with Session(client.app.state.engine) as db:
        db.scalar(select(User).where(User.username == 'bob')).avatar = 'photo-data'
        db.commit()
    client.post('/api/v1/me/guest-collections/' + token + '/join', headers=headers('bob'), json={})
    assert client.get('/api/v1/collections/' + c['id'], headers=headers()).json()['participants'][0]['avatar'] == 'photo-data'
    assert 'photo-data' not in client.get('/api/v1/public/collections/' + token).text
