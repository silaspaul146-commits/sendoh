import time
from sqlalchemy import select, func
from app.models import Notification, Participant, Collection, PushDevice, PushDelivery, User
from app.push import process_one
from test_collections import headers
from test_mesomb_lifecycle import client, setup, create, due


def reminder(client, collection, user='alice', method='post'):
    return getattr(client, method)(f"/api/v1/collections/{collection['id']}/reminders",
                                  headers=headers(user))


def test_owner_reminds_only_joined_outstanding_member_once(client):
    c, _ = setup(client)
    assert reminder(client,c,method='get').json()['eligible_count'] == 1
    assert reminder(client,c,'bob').status_code == 404
    first = reminder(client,c)
    assert first.status_code == 200
    assert first.json()['reminded_count'] == 1
    assert reminder(client,c).json()['reminded_count'] == 0
    assert reminder(client,c,method='get').json()['eligible_count'] == 0
    inbox = client.get('/api/v1/me/notifications',headers=headers('bob')).json()['items']
    notice = next(n for n in inbox if n['kind'] == 'CONTRIBUTION_REMINDER')
    assert notice['title'] == 'Contribution reminder for Family support'
    detail = client.get(f"/api/v1/me/invitations/{notice['participant_id']}?version={notice['invitation_version']}", headers=headers('bob'))
    assert detail.status_code == 200
    assert detail.json()['invitation_state'] == 'ACCEPTED'


def test_pending_and_paid_members_are_not_reminded(client):
    c, _ = setup(client)
    pid = create(client,c).json()['id']
    assert reminder(client,c).json()['reminded_count'] == 0
    due(client,pid)
    assert reminder(client,c).json()['reminded_count'] == 0


def test_partial_member_remains_eligible_but_manual_or_cancelled_does_not(client):
    c, _ = setup(client)
    with client.app.state.sessions() as db:
        p = db.scalar(select(Participant).where(Participant.collection_id==c['id']))
        p.expected_amount = 2000
        db.add(Participant(collection_id=c['id'],name='Offline member',expected_amount=2000))
        db.commit()
    pid = create(client,c).json()['id']; due(client,pid)
    assert reminder(client,c,method='get').json()['eligible_count'] == 1
    with client.app.state.sessions() as db:
        db.get(Collection,c['id']).status = 'DRAFT'; db.commit()
    assert reminder(client,c).status_code == 409


def test_reminder_cooldown_survives_read_and_crosses_midnight(client, monkeypatch):
    c, _ = setup(client)
    clock = [int(time.time()) // 86400 * 86400 + 86300]
    monkeypatch.setattr('app.collection_reminders.time.time', lambda: clock[0])
    assert reminder(client,c).json()['reminded_count'] == 1
    with client.app.state.sessions() as db:
        n = db.scalar(select(Notification).where(Notification.kind=='CONTRIBUTION_REMINDER'))
        n.read_at = clock[0]; db.commit()
    clock[0] += 200
    assert reminder(client,c).json()['reminded_count'] == 0
    clock[0] += 86400
    assert reminder(client,c).json()['reminded_count'] == 1
    with client.app.state.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Notification).where(Notification.kind=='CONTRIBUTION_REMINDER')) == 2


class Sender:
    def __init__(self): self.sent=[]
    def send(self,token,notification_id,**kwargs): self.sent.append((notification_id,kwargs))


def test_queued_reminder_is_skipped_after_payment(client):
    c, _ = setup(client)
    with client.app.state.sessions() as db:
        bob = db.scalar(select(User).where(User.username=='bob'))
        db.add(PushDevice(user_id=bob.id, token='test-token', token_hash='test-hash',
            family_id='dev:'+bob.id, platform='android', active=1,
            updated_at=int(time.time()), expires_at=int(time.time())+86400))
        db.commit()
    assert reminder(client,c).json()['reminded_count'] == 1
    pid=create(client,c).json()['id']; due(client,pid)
    sender=Sender()
    while process_one(client.app.state.sessions,sender,'development'): pass
    with client.app.state.sessions() as db:
        n=db.scalar(select(Notification).where(Notification.kind=='CONTRIBUTION_REMINDER'))
        job=db.scalar(select(PushDelivery).where(PushDelivery.notification_id==n.id))
        assert job.state=='SKIPPED'
        assert not any(item[0]==n.id for item in sender.sent)


def test_push_reminder_names_its_collection(client):
    c, _ = setup(client)
    with client.app.state.sessions() as db:
        bob = db.scalar(select(User).where(User.username=='bob'))
        db.add(PushDevice(user_id=bob.id, token='test-token', token_hash='test-hash',
            family_id='dev:'+bob.id, platform='android', active=1,
            updated_at=int(time.time()), expires_at=int(time.time())+86400))
        db.commit()
    assert reminder(client,c).json()['reminded_count'] == 1
    sender = Sender()
    while process_one(client.app.state.sessions,sender,'development'): pass
    assert any(message.get('body')=='Contribution reminder for Family support'
               for _,message in sender.sent)
