import time
import uuid
import pytest
from sqlalchemy import select, func
from sqlalchemy.orm import Session
from app.models import Participant, User, PhoneIdentity, Activity, InvitationRate
from test_collections import client, headers


def collection(client, **patch):
    response = client.post('/api/v1/collections', headers=headers(key=str(uuid.uuid4())),
                           json={'name': 'Family support', **patch})
    assert response.status_code == 201, response.text
    return response.json()


def invite(client, c, body=None, key=None, user='alice'):
    return client.post(f"/api/v1/collections/{c['id']}/invitations",
                       headers=headers(user, key or str(uuid.uuid4())),
                       json=body or {'username': '@BOB'})


def respond(client, p, decision='accept', user='bob'):
    return client.post(f"/api/v1/me/invitations/{p['id']}/respond",
                       headers=headers(user), json={'decision': decision})


def cancel(client, c, p, user='alice'):
    return client.post(f"/api/v1/collections/{c['id']}/invitations/{p['id']}/cancel",
                       headers=headers(user), json={})


def bind_phone(client, username='bob', phone='+237690123456'):
    with Session(client.app.state.engine) as db:
        user = db.scalar(select(User).where(User.username == username))
        db.add(PhoneIdentity(user_id=user.id, phone=phone))
        db.commit()


def test_accept_binds_identity_without_granting_organizer_access(client):
    c = collection(client, participants=[{'name': 'Private roster person'}])
    p = invite(client, c).json()
    assert p['invitation_state'] == 'PENDING' and p['user_id'] is None
    assert client.get('/api/v1/collections/' + c['id'], headers=headers()).headers['Cache-Control'] == 'no-store'
    assert client.get('/api/v1/me/invitations', headers=headers()).json() == []
    inbox = client.get('/api/v1/me/invitations', headers=headers('bob')).json()
    assert len(inbox) == 1
    assert 'Private roster person' not in str(inbox)
    assert 'participants' not in inbox[0]['collection']
    accepted = respond(client, p)
    assert accepted.status_code == 200, accepted.text
    assert accepted.json()['invitation_state'] == 'ACCEPTED'
    assert respond(client, p).json() == accepted.json()
    assert client.get('/api/v1/me/invitations', headers=headers('bob')).json() == []
    joined = client.get('/api/v1/me/joined-collections', headers=headers('bob')).json()
    assert len(joined) == 1 and joined[0]['id'] == p['id']
    assert client.get('/api/v1/collections/' + c['id'], headers=headers('bob')).status_code == 404
    assert client.get('/api/v1/collections', headers=headers('bob')).json() == []
    detail = client.get('/api/v1/collections/' + c['id'], headers=headers()).json()
    linked = next(row for row in detail['participants'] if row['id'] == p['id'])
    assert linked['identity_verified'] and linked['username'] == 'bob'
    assert detail['collected_amount'] == 0
    public = client.get('/api/v1/public/collections/' + c['share_url'].split('/')[-1]).json()
    assert 'participants' not in public
    assert client.get('/health').json()['payments_enabled'] is False
    assert cancel(client, c, p).status_code == 409


def test_strangers_cannot_invite_respond_or_cancel(client):
    c = collection(client)
    p = invite(client, c).json()
    assert invite(client, c, user='bob').status_code == 404
    assert respond(client, p, user='alice').status_code == 404
    assert cancel(client, c, p, user='bob').status_code == 404
    assert client.get('/api/v1/me/invitations').status_code == 401
    assert client.post(f"/api/v1/me/invitations/{p['id']}/respond", json={'decision':'accept'}).status_code == 401


def test_manual_row_binding_preserves_expectation_and_no_duplicates(client):
    bind_phone(client)
    c = collection(client, mode='EXPECTED_TOTAL', expected_amount=3000,
                   participants=[{'name':'Bobo', 'expected_amount':5000}])
    manual = c['participants'][0]
    assert manual['invitation_state'] == 'UNVERIFIED'
    payload = {'username':'bob', 'participant_id':manual['id']}
    first = invite(client, c, payload, key='repeat-invite-1')
    assert first.status_code == 201
    assert first.json()['id'] == manual['id'] and first.json()['expected_amount'] == 5000
    assert invite(client, c, payload, key='repeat-invite-1').json() == first.json()
    assert invite(client, c, {'phone':'+237690123456'}).json()['id'] == manual['id']
    assert '+237690123456' not in first.text
    assert invite(client, c, {'username':'alice'}, key='repeat-invite-1').status_code == 409
    with Session(client.app.state.engine) as db:
        assert db.scalar(select(func.count()).select_from(Participant)) == 1
        assert db.scalar(select(func.count()).select_from(Activity)) == 2


def test_unregistered_phone_invitation_appears_after_phone_verification(client):
    c = collection(client)
    p = invite(client, c, {'phone':'+237690123456', 'name':'Bobo'}).json()
    assert client.get('/api/v1/me/invitations', headers=headers('bob')).json() == []
    # PhoneIdentity is created by the phase-one OTP verification flow.
    bind_phone(client)
    assert client.get('/api/v1/me/invitations', headers=headers('bob')).json()[0]['id'] == p['id']
    assert respond(client, p).status_code == 200
    with Session(client.app.state.engine) as db:
        row = db.get(Participant, p['id'])
        assert row.user_id == row.invited_user_id
        assert row.name == 'bob'


def test_decline_cancel_expiry_and_reinvite_rules(client):
    c = collection(client)
    p = invite(client, c).json()
    assert cancel(client, c, p).json()['invitation_state'] == 'CANCELLED'
    assert cancel(client, c, p).status_code == 200
    assert respond(client, p).status_code == 409
    assert client.get('/api/v1/me/invitations', headers=headers('bob')).json() == []
    assert invite(client, c).json()['id'] == p['id']
    with Session(client.app.state.engine) as db:
        db.get(Participant, p['id']).expires_at = int(time.time()) - 1
        db.commit()
    assert client.get('/api/v1/me/invitations', headers=headers('bob')).json() == []
    assert respond(client, p).status_code == 409
    assert client.get('/api/v1/collections/' + c['id'], headers=headers()).json()['participants'][0]['invitation_state'] == 'EXPIRED'
    assert invite(client, c).json()['invitation_state'] == 'PENDING'
    assert respond(client, p, 'decline').json()['invitation_state'] == 'DECLINED'
    assert respond(client, p, 'decline').status_code == 200
    assert respond(client, p).status_code == 409
    assert invite(client, c).status_code == 409
    assert client.get('/api/v1/me/joined-collections', headers=headers('bob')).json() == []


@pytest.mark.parametrize('body', [
    {'username':'bob', 'phone':'+237690123456'}, {'name':'No identity'},
    {'phone':'690123456'}, {'username':'bob', 'expected_amount':0},
    {'username':'bob', 'expected_amount':True}, {'username':'bob', 'user_id':'spoof'},
])
def test_invalid_invites_do_not_create_rows(client, body):
    c = collection(client)
    assert invite(client, c, body).status_code == 422
    assert client.get('/api/v1/collections/' + c['id'], headers=headers()).json()['participants'] == []


def test_drafts_self_invites_unknown_users_and_wrong_manual_rows(client):
    draft = collection(client, publish=False)
    assert invite(client, draft).status_code == 409
    c = collection(client)
    assert invite(client, c, {'username':'alice'}).status_code == 409
    assert invite(client, c, {'username':'missing'}).status_code == 404
    assert invite(client, c, {'username':'bob', 'expected_amount':500}).status_code == 422
    other = collection(client, participants=[{'name':'Someone'}])
    assert invite(client, c, {'username':'bob','participant_id':other['participants'][0]['id']}).status_code == 404


def test_no_silent_reassignment_or_duplicate_manual_binding(client):
    c = collection(client, participants=[{'name':'One'}, {'name':'Two'}])
    first, second = c['participants']
    assert invite(client, c, {'username':'bob','participant_id':first['id']}).status_code == 201
    assert invite(client, c, {'phone':'+237670111111','participant_id':first['id']}).status_code == 409
    assert invite(client, c, {'username':'bob','participant_id':second['id']}).status_code == 409


def test_rate_limit_includes_failed_lookups_and_resets(client):
    c = collection(client)
    for _ in range(20):
        assert invite(client, c, {'username':'missing'}).status_code == 404
    assert invite(client, c).status_code == 429
    with Session(client.app.state.engine) as db:
        db.scalar(select(InvitationRate)).window_start -= 61
        db.commit()
    assert invite(client, c).status_code == 201


def test_concurrent_invites_and_competing_decisions(client):
    if client.app.state.engine.dialect.name != 'postgresql':
        pytest.skip('PostgreSQL row-locking coverage runs in CI')
    from concurrent.futures import ThreadPoolExecutor
    c = collection(client)
    with ThreadPoolExecutor(max_workers=4) as pool:
        responses = list(pool.map(lambda _: invite(client, c), range(4)))
    assert all(r.status_code == 201 for r in responses)
    assert len({r.json()['id'] for r in responses}) == 1
    p = responses[0].json()
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda decision: respond(client, p, decision), ['accept','decline']))
    assert sorted(r.status_code for r in results) == [200,409]
