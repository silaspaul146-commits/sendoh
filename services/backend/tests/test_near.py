"""Near2Pay codes identify a person for a short time; they never move money."""
from sqlalchemy import select, func, update

from app.models import NearCode, PersonOrder, ProviderPayment
from app.near import MAX_FAILURES
from test_collections import headers
from test_mesomb_lifecycle import client  # noqa: F401


def show(client, user='alice', amount=None):
    return client.post('/api/v1/near/codes', headers=headers(user),
                       json={} if amount is None else {'amount': amount})


def resolve(client, code, user='bob'):
    return client.post('/api/v1/near/resolve', headers=headers(user), json={'code': code})


def test_scanned_or_typed_code_shows_the_person_and_amount(client):
    shown = show(client, amount=2500)
    assert shown.status_code == 201, shown.text
    code = shown.json()
    assert code['qr'].startswith('sendoh:near:') and len(code['short_code']) == 7
    assert code['lifetime'] == 120
    for value in (code['qr'], code['short_code'], code['short_code'].replace('-', '').lower()):
        r = resolve(client, value)
        assert r.status_code == 200, r.text
        assert r.json()['person'] == {'id': r.json()['person']['id'], 'name': 'alice', 'identity': '@alice'}
        assert r.json()['amount'] == 2500
    # Identifying someone creates no order and no charge.
    with client.app.state.sessions() as db:
        assert db.scalar(select(func.count()).select_from(PersonOrder)) == 0
        assert db.scalar(select(func.count()).select_from(ProviderPayment)) == 0
        # Only hashes are stored.
        row = db.scalar(select(NearCode))
        assert code['qr'] not in (row.token_hash, row.short_hash)


def test_expired_and_replaced_codes_stop_working(client):
    first = show(client).json()
    second = show(client).json()
    assert resolve(client, first['short_code']).status_code == 404
    assert resolve(client, second['short_code']).status_code == 200
    with client.app.state.sessions() as db:
        db.execute(update(NearCode).values(expires_at=0))
        db.commit()
    assert resolve(client, second['qr']).status_code == 404


def test_own_code_is_refused(client):
    code = show(client).json()
    assert resolve(client, code['short_code'], user='alice').status_code == 409


def test_collection_code_says_contribute_and_names_the_organizer(client):
    from test_invitations import collection
    from test_mesomb_lifecycle import setup
    c, token = setup(client)  # alice organizes, bob has joined
    shown = client.post('/api/v1/near/codes', headers=headers('alice'),
                        json={'collection_id': c['id'], 'amount': 1000})
    assert shown.status_code == 201, shown.text
    assert shown.json()['purpose'] == 'COLLECTION'
    r = resolve(client, shown.json()['short_code'], user='bob').json()
    assert r['purpose'] == 'COLLECTION' and 'person' not in r
    assert r['collection']['name'] == c['name'] and r['collection']['token'] == token
    assert r['organizer']['name'] == 'alice' and r['membership'] == 'ACCEPTED' and r['amount'] == 1000
    assert resolve(client, shown.json()['short_code'], user='eve').json()['membership'] == 'NOT_JOINED'
    # Someone else's collection cannot be presented.
    other = collection(client)
    assert client.post('/api/v1/near/codes', headers=headers('bob'),
                       json={'collection_id': other['id']}).status_code == 404


def test_personal_code_is_labelled_as_a_person(client):
    r = resolve(client, show(client).json()['short_code']).json()
    assert r['purpose'] == 'PERSON' and r['person']['name'] == 'alice'


def test_guessing_short_codes_is_throttled(client):
    for _ in range(MAX_FAILURES):
        assert resolve(client, 'ZZZ-ZZZ').status_code == 404
    real = show(client).json()
    assert resolve(client, real['short_code']).status_code == 429
    # Another payer is unaffected.
    assert resolve(client, real['short_code'], user='eve').status_code == 200
