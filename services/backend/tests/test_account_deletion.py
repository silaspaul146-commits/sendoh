"""Deleting an account: identity goes, money records stay, nothing is left mid-flight."""
import uuid

from sqlalchemy import select

from app.models import Participant, PhoneIdentity, ProviderPayment, User
from test_collections import headers
from test_mesomb_lifecycle import client, create, due, setup  # noqa: F401

DELETE = '/api/v1/me/account/delete'


def test_member_deletes_account_and_records_stay(client):
    c, _ = setup(client)                         # bob joined alice's collection
    pid = create(client, c).json()['id']
    # A payment still confirming holds the deletion.
    check = client.get('/api/v1/me/account/deletion', headers=headers('bob')).json()
    assert check['can_delete'] is False and check['blockers'][0]['code'] == 'PAYMENT_CONFIRMING'
    assert client.post(DELETE, headers=headers('bob'), json={'confirm': 'DELETE'}).status_code == 409
    due(client, pid)
    assert client.post(DELETE, headers=headers('bob'), json={'confirm': 'yes'}).status_code == 422
    r = client.post(DELETE, headers=headers('bob'), json={'confirm': 'DELETE'})
    assert r.status_code == 200, r.text
    # Signed out everywhere: the old credential no longer works.
    assert client.get('/api/v1/me/account/deletion', headers=headers('bob')).status_code == 401
    with client.app.state.sessions() as db:
        bob = db.scalar(select(User).where(User.display_name == 'Deleted user'))
        assert bob.username is None and bob.avatar is None
        assert db.scalar(select(PhoneIdentity).where(PhoneIdentity.user_id == bob.id)) is None
        assert db.scalar(select(Participant.name).where(Participant.user_id == bob.id)) == 'Former member'
        # The organizer's ledger keeps the confirmed money.
        assert db.get(ProviderPayment, pid).status == 'SUCCEEDED'
    totals = client.get('/api/v1/collections/' + c['id'], headers=headers()).json()['totals']
    assert totals['confirmed_amount'] == 1000


def test_organizer_must_settle_before_deleting(client):
    c, _ = setup(client)
    due(client, create(client, c).json()['id'])
    check = client.get('/api/v1/me/account/deletion', headers=headers()).json()
    assert [b['code'] for b in check['blockers']] == ['COLLECTION_HOLDS_MONEY']
    assert c['name'] in check['blockers'][0]['message']
    assert client.post(DELETE, headers=headers(), json={'confirm': 'DELETE'}).status_code == 409


def test_empty_collection_closes_with_the_account(client):
    r = client.post('/api/v1/collections', headers=headers(key=str(uuid.uuid4())), json={
        'name': 'Empty', 'target_amount': 1000, 'mode': 'ANY_AMOUNT'})
    assert r.status_code in (200, 201), r.text
    assert client.post(DELETE, headers=headers(), json={'confirm': 'DELETE'}).status_code == 200
    token = r.json()['share_url'].split('/')[-1]
    assert client.get('/api/v1/public/collections/' + token).json()['status'] == 'CLOSED'
