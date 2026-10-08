import time
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from app.main import create_app
from app.models import Base, OtpChallenge, AuthSession

PHONE = '+237670123456'

@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv('SENDOH_DEV_OTP_DIR', str(tmp_path / 'codes'))
    app = create_app(f'sqlite:///{tmp_path}/auth.db')
    Base.metadata.create_all(app.state.engine)
    with TestClient(app) as c:
        c.code_dir = tmp_path / 'codes'
        yield c
    app.state.engine.dispose()


def issue(client, phone=PHONE):
    response = client.post('/api/v1/auth/code', json={'phone': phone})
    assert response.status_code == 200
    data = response.json()
    code = (client.code_dir / data['challenge_id']).read_text()
    assert code not in response.text
    return {'phone': phone, 'challenge_id': data['challenge_id'], 'code': code}


def login(client):
    payload = issue(client)
    response = client.post('/api/v1/auth/verify', json=payload)
    assert response.status_code == 200
    return response.json(), payload


def test_profile_collection_name_and_logout(client):
    result, payload = login(client)
    headers = {'Authorization': 'Bearer ' + result['access_token']}
    assert result['user']['profile_complete'] is False
    assert client.post('/api/v1/collections', json={'name':'Birthday'}, headers={**headers,'Idempotency-Key':'test-auth-123'}).status_code == 409
    assert client.post('/api/v1/me/profile', json={'display_name':'  Kboy  ', 'username':'kboy'}, headers=headers).json()['display_name'] == 'Kboy'
    created = client.post('/api/v1/collections', json={'name':'Birthday'}, headers={**headers,'Idempotency-Key':'test-auth-123'}).json()
    token = created['share_url'].split('/')[-1]
    public = client.get('/api/v1/public/collections/' + token).json()
    assert public['organizer_name'] == 'Kboy'
    assert 'phone' not in public
    assert not (client.code_dir / payload['challenge_id']).exists()
    assert client.post('/api/v1/auth/verify', json=payload).status_code == 400
    assert client.post('/api/v1/auth/logout', json={}, headers=headers).status_code == 200
    assert client.get('/api/v1/me', headers=headers).status_code == 401


def test_resend_and_attempt_limits(client):
    payload = issue(client)
    assert client.post('/api/v1/auth/code', json={'phone':PHONE}).status_code == 429
    wrong = '000000' if payload['code'] != '000000' else '111111'
    for _ in range(5):
        assert client.post('/api/v1/auth/verify', json={**payload,'code':wrong}).status_code == 400
    assert client.post('/api/v1/auth/verify', json=payload).status_code == 400
    with Session(client.app.state.engine) as db:
        db.get(OtpChallenge, PHONE).sent_at -= 61
        db.commit()
    fresh = issue(client)
    assert client.post('/api/v1/auth/verify', json=payload).status_code == 400
    assert client.post('/api/v1/auth/verify', json=fresh).status_code == 200


def test_expired_code_and_session(client):
    payload = issue(client)
    with Session(client.app.state.engine) as db:
        db.get(OtpChallenge, PHONE).expires_at = int(time.time()) - 1
        db.commit()
    assert client.post('/api/v1/auth/verify', json=payload).status_code == 400
    result = client.post('/api/v1/auth/verify', json=issue(client, '+237690123456')).json()
    with Session(client.app.state.engine) as db:
        from app.auth import digest
        db.get(AuthSession, digest(result['access_token'])).expires_at = 0
        db.commit()
    assert client.get('/api/v1/me', headers={'Authorization':'Bearer '+result['access_token']}).status_code == 401


def test_returning_user_and_isolation(client):
    first, _ = login(client)
    with Session(client.app.state.engine) as db:
        db.get(OtpChallenge, PHONE).sent_at -= 61
        db.commit()
    again, _ = login(client)
    assert again['user']['id'] == first['user']['id']
    other = client.post('/api/v1/auth/verify', json=issue(client, '+237690123456')).json()
    assert other['user']['id'] != first['user']['id']
    assert client.post('/api/v1/me/profile', json={'display_name':'Spoof'}).status_code == 401
    assert client.post('/api/v1/me/profile', json={'display_name':' '}, headers={'Authorization':'Bearer '+first['access_token']}).status_code == 422


@pytest.mark.parametrize('phone', ['670123456', '+123456789', '+237', '+237170123456'])
def test_invalid_phone(client, phone):
    assert client.post('/api/v1/auth/code', json={'phone':phone}).status_code == 422
