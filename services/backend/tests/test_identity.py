import base64
from io import BytesIO
import time
import pytest
from PIL import Image
from sqlalchemy.orm import Session
from app.auth import digest
from app.models import RefreshSession
from test_auth import client, login, issue

def headers(result):
    return {'Authorization': 'Bearer ' + result['access_token']}

def test_username_normalization_unique_and_immutable(client):
    first, _ = login(client)
    assert client.post('/api/v1/me/profile', headers=headers(first), json={
        'display_name': 'Rene', 'username': '  Rene_237  '}).json()['username'] == 'rene_237'
    other = client.post('/api/v1/auth/verify', json=issue(client, '+237690123456')).json()
    response = client.post('/api/v1/me/profile', headers=headers(other), json={
        'display_name': 'Another', 'username': 'RENE_237'})
    assert response.status_code == 409
    assert client.get('/api/v1/me', headers=headers(other)).json()['display_name'] == ''
    assert client.post('/api/v1/me/profile', headers=headers(first), json={
        'display_name': 'Rene', 'username': 'different'}).status_code == 409
    assert client.get('/api/v1/me', headers=headers(first)).json()['profile_complete'] is True

@pytest.mark.parametrize('username', ['ab', '9rene', 'foo.bar', 'réne', 'admin', 'sendoh', 'a' * 25])
def test_invalid_username(client, username):
    result, _ = login(client)
    assert client.post('/api/v1/me/profile', headers=headers(result), json={
        'display_name': 'Rene', 'username': username}).status_code == 422

def test_photo_is_sanitized_private_and_removable(client):
    result, _ = login(client)
    output = BytesIO()
    Image.new('RGB', (600, 300), 'teal').save(output, 'PNG')
    response = client.post('/api/v1/me/profile', headers=headers(result), json={
        'display_name': 'Rene', 'username': 'rene237',
        'avatar': base64.b64encode(output.getvalue()).decode()})
    assert response.status_code == 200
    image = Image.open(BytesIO(base64.b64decode(response.json()['avatar'])))
    assert image.format == 'JPEG' and image.size == (256, 256)
    assert not image.getexif()
    assert response.headers['Cache-Control'] == 'no-store'
    assert client.get('/api/v1/me').status_code == 401
    # Omitting the image preserves it. Null removes it.
    assert client.post('/api/v1/me/profile', headers=headers(result), json={'display_name':'Rene'}).json()['avatar']
    assert client.post('/api/v1/me/profile', headers=headers(result), json={'display_name':'Rene', 'avatar':None}).json()['avatar'] is None

@pytest.mark.parametrize(
    'avatar',
    ['not base64', base64.b64encode(b'<svg/>').decode(), 'A' * 270001],
    # Pytest exports each test ID via PYTEST_CURRENT_TEST. Explicit short IDs
    # prevent the oversized payload exceeding Windows' environment-value limit.
    ids=['invalid-base64', 'unsupported-svg', 'oversized-avatar'],
)
def test_rejects_invalid_photo(client, avatar):
    result, _ = login(client)
    assert client.post('/api/v1/me/profile', headers=headers(result), json={
        'display_name': 'Rene', 'avatar': avatar}).status_code == 422

def test_refresh_rotates_and_replay_revokes_family(client):
    first, _ = login(client)
    next_response = client.post('/api/v1/auth/refresh', json={'refresh_token': first['refresh_token']})
    assert next_response.status_code == 200
    second = next_response.json()
    assert second['refresh_token'] != first['refresh_token']
    assert client.get('/api/v1/me', headers=headers(first)).status_code == 401
    assert client.get('/api/v1/me', headers=headers(second)).status_code == 200
    assert client.post('/api/v1/auth/refresh', json={'refresh_token':first['refresh_token']}).status_code == 401
    assert client.get('/api/v1/me', headers=headers(second)).status_code == 401
    assert client.post('/api/v1/auth/refresh', json={'refresh_token':second['refresh_token']}).status_code == 401

def test_logout_and_expiry_invalidate_refresh(client):
    first, _ = login(client)
    assert client.post('/api/v1/auth/logout', headers=headers(first)).status_code == 200
    assert client.post('/api/v1/auth/refresh', json={'refresh_token':first['refresh_token']}).status_code == 401
    other = client.post('/api/v1/auth/verify', json=issue(client, '+237690123456')).json()
    with Session(client.app.state.engine) as db:
        db.get(RefreshSession, digest(other['refresh_token'])).expires_at = int(time.time()) - 1
        db.commit()
    assert client.post('/api/v1/auth/refresh', json={'refresh_token':other['refresh_token']}).status_code == 401

def test_legacy_name_only_profile_needs_completion(client):
    first, _ = login(client)
    result = client.post('/api/v1/me/profile', headers=headers(first), json={'display_name':'Legacy'}).json()
    assert result['profile_complete'] is False
    assert result['username'] is None
    assert client.post('/api/v1/collections', headers={**headers(first), 'Idempotency-Key':'incomplete-user'},
                       json={'name':'Blocked until complete'}).status_code == 409

def test_upload_limit(client):
    assert client.post('/api/v1/me/profile', content=b'x' * 400001,
                       headers={'Content-Type':'application/json'}).status_code == 413




















# import base64
# from io import BytesIO
# import time
# import pytest
# from PIL import Image
# from sqlalchemy.orm import Session
# from app.auth import digest
# from app.models import RefreshSession
# from test_auth import client, login, issue

# def headers(result):
#     return {'Authorization': 'Bearer ' + result['access_token']}

# def test_username_normalization_unique_and_immutable(client):
#     first, _ = login(client)
#     assert client.post('/api/v1/me/profile', headers=headers(first), json={
#         'display_name': 'Rene', 'username': '  Rene_237  '}).json()['username'] == 'rene_237'
#     other = client.post('/api/v1/auth/verify', json=issue(client, '+237690123456')).json()
#     response = client.post('/api/v1/me/profile', headers=headers(other), json={
#         'display_name': 'Another', 'username': 'RENE_237'})
#     assert response.status_code == 409
#     assert client.get('/api/v1/me', headers=headers(other)).json()['display_name'] == ''
#     assert client.post('/api/v1/me/profile', headers=headers(first), json={
#         'display_name': 'Rene', 'username': 'different'}).status_code == 409
#     assert client.get('/api/v1/me', headers=headers(first)).json()['profile_complete'] is True

# @pytest.mark.parametrize('username', ['ab', '9rene', 'foo.bar', 'réne', 'admin', 'sendoh', 'a' * 25])
# def test_invalid_username(client, username):
#     result, _ = login(client)
#     assert client.post('/api/v1/me/profile', headers=headers(result), json={
#         'display_name': 'Rene', 'username': username}).status_code == 422

# def test_photo_is_sanitized_private_and_removable(client):
#     result, _ = login(client)
#     output = BytesIO()
#     Image.new('RGB', (600, 300), 'teal').save(output, 'PNG')
#     response = client.post('/api/v1/me/profile', headers=headers(result), json={
#         'display_name': 'Rene', 'username': 'rene237',
#         'avatar': base64.b64encode(output.getvalue()).decode()})
#     assert response.status_code == 200
#     image = Image.open(BytesIO(base64.b64decode(response.json()['avatar'])))
#     assert image.format == 'JPEG' and image.size == (256, 256)
#     assert not image.getexif()
#     assert response.headers['Cache-Control'] == 'no-store'
#     assert client.get('/api/v1/me').status_code == 401
#     # Omitting the image preserves it. Null removes it.
#     assert client.post('/api/v1/me/profile', headers=headers(result), json={'display_name':'Rene'}).json()['avatar']
#     assert client.post('/api/v1/me/profile', headers=headers(result), json={'display_name':'Rene', 'avatar':None}).json()['avatar'] is None

# @pytest.mark.parametrize('avatar', ['not base64', base64.b64encode(b'<svg/>').decode(), 'A' * 270001])
# def test_rejects_invalid_photo(client, avatar):
#     result, _ = login(client)
#     assert client.post('/api/v1/me/profile', headers=headers(result), json={
#         'display_name': 'Rene', 'avatar': avatar}).status_code == 422

# def test_refresh_rotates_and_replay_revokes_family(client):
#     first, _ = login(client)
#     next_response = client.post('/api/v1/auth/refresh', json={'refresh_token': first['refresh_token']})
#     assert next_response.status_code == 200
#     second = next_response.json()
#     assert second['refresh_token'] != first['refresh_token']
#     assert client.get('/api/v1/me', headers=headers(first)).status_code == 401
#     assert client.get('/api/v1/me', headers=headers(second)).status_code == 200
#     assert client.post('/api/v1/auth/refresh', json={'refresh_token':first['refresh_token']}).status_code == 401
#     assert client.get('/api/v1/me', headers=headers(second)).status_code == 401
#     assert client.post('/api/v1/auth/refresh', json={'refresh_token':second['refresh_token']}).status_code == 401

# def test_logout_and_expiry_invalidate_refresh(client):
#     first, _ = login(client)
#     assert client.post('/api/v1/auth/logout', headers=headers(first)).status_code == 200
#     assert client.post('/api/v1/auth/refresh', json={'refresh_token':first['refresh_token']}).status_code == 401
#     other = client.post('/api/v1/auth/verify', json=issue(client, '+237690123456')).json()
#     with Session(client.app.state.engine) as db:
#         db.get(RefreshSession, digest(other['refresh_token'])).expires_at = int(time.time()) - 1
#         db.commit()
#     assert client.post('/api/v1/auth/refresh', json={'refresh_token':other['refresh_token']}).status_code == 401

# def test_legacy_name_only_profile_needs_completion(client):
#     first, _ = login(client)
#     result = client.post('/api/v1/me/profile', headers=headers(first), json={'display_name':'Legacy'}).json()
#     assert result['profile_complete'] is False
#     assert result['username'] is None
#     assert client.post('/api/v1/collections', headers={**headers(first), 'Idempotency-Key':'incomplete-user'},
#                        json={'name':'Blocked until complete'}).status_code == 409

# def test_upload_limit(client):
#     assert client.post('/api/v1/me/profile', content=b'x' * 400001,
#                        headers={'Content-Type':'application/json'}).status_code == 413
