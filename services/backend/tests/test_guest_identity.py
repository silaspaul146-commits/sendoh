from sqlalchemy.orm import Session
from sqlalchemy import select
from app.models import User
from test_collections import client, headers
from test_invitations import collection, invite, cancel, bind_phone


def test_personal_link_is_locator_not_authentication(client):
    c = collection(client, participants=[{'name':'Private manual name'}])
    p = invite(client,c).json()
    path=f"/api/v1/collections/{c['id']}/invitations/{p['id']}/link"
    link=client.get(path,headers=headers()).json()['url']
    assert link.endswith('?v=1')
    assert client.get(path,headers=headers('bob')).status_code==404
    detail=f"/api/v1/me/invitations/{p['id']}?version=1"
    assert client.get(detail).status_code==401
    assert client.get(detail,headers=headers()).status_code==404
    result=client.get(detail,headers=headers('bob'))
    assert result.status_code==200
    assert 'Private manual name' not in result.text
    cancel(client,c,p)
    invite(client,c)
    assert client.get(detail,headers=headers('bob')).status_code==404
    assert client.post(f"/api/v1/me/invitations/{p['id']}/respond",headers=headers('bob'),json={'decision':'accept','version':1}).status_code==409


def test_phone_verified_guest_can_join_without_username(client):
    c=collection(client)
    p=invite(client,c,{'phone':'+237690123456','name':'Guest'}).json()
    bind_phone(client)
    with Session(client.app.state.engine) as db:
        user=db.scalar(select(User).where(User.username=='bob'))
        user.username=None
        db.commit()
    result=client.post(f"/api/v1/me/invitations/{p['id']}/respond",headers=headers('bob'),json={'decision':'accept','version':1})
    assert result.status_code==200,result.text
    context=client.get('/api/v1/me/guest-collections/'+c['share_url'].split('/')[-1],headers=headers('bob')).json()
    assert context['participant']['id']==p['id']
    assert context['phone']=='+237690123456'
    assert context['attribution']=='self' and context['payments_enabled'] is False
    assert client.get('/api/v1/me/guest-collections/'+c['share_url'].split('/')[-1],headers=headers()).status_code==403


def test_notification_detail_requires_recipient(client):
    c=collection(client);invite(client,c)
    rows=client.get('/api/v1/me/notifications',headers=headers('bob')).json()['items']
    path='/api/v1/me/notifications/'+rows[0]['id']
    assert client.get(path,headers=headers('bob')).status_code==200
    assert client.get(path,headers=headers()).status_code==404


def test_successful_mutation_wakes_push_worker_after_commit(client):
    class Wake:
        count=0
        def set(self): self.count+=1
    wake=Wake()
    client.app.state.push_wake=wake
    c=collection(client)
    before=wake.count
    invite(client,c)
    assert wake.count==before+1
    before=wake.count
    client.get('/api/v1/me/notifications',headers=headers('bob'))
    assert wake.count==before
