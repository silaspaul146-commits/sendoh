"""Mobile Money numbers are how you pay and get paid, not who you are."""
from sqlalchemy import select

from app.models import PhoneIdentity, User
from app.money_numbers import network
from test_collections import headers
from test_invitations import bind_phone
from test_mesomb_lifecycle import client  # noqa: F401

BASE = '/api/v1/me/money-numbers'


def add(client, phone, **kw):
    return client.post(BASE, headers=headers('bob'), json=dict(phone=phone, **kw))


def test_network_from_prefix():
    assert network('671234589') == 'MTN' and network('652000000') == 'MTN' and network('681000000') == 'MTN'
    assert network('699876512') == 'ORANGE' and network('656000000') == 'ORANGE' and network('+237686000000') == 'ORANGE'
    assert network('620000000') is None


def test_sign_in_number_is_already_verified_and_becomes_default(client):
    bind_phone(client)  # bob signs in with +237690123456
    r = add(client, '690123456')
    assert r.status_code == 200, r.text
    n = r.json()['number']
    assert n['verified'] and n['is_sign_in_number'] and n['method'] == 'ORANGE'
    assert n['pay_default'] and n['receive_default']
    assert r.json()['challenge'] is None
    assert n['masked'] == '690 •• •• 56'


def test_another_number_is_verified_by_sms_code(client, monkeypatch):
    monkeypatch.setenv('SENDOH_SHOW_TEST_CODES', '1')
    bind_phone(client)
    add(client, '690123456')
    r = add(client, '671234589', receive_default=True)
    assert r.status_code == 200, r.text
    n, c = r.json()['number'], r.json()['challenge']
    assert not n['verified'] and n['method'] == 'MTN' and c['test_code']
    # Unverified: not a default yet, and the old number still receives.
    assert {x['masked']: x['receive_default'] for x in r.json()['numbers']} == {'690 •• •• 56': True, '671 •• •• 89': False}
    wrong = '000000' if c['test_code'] != '000000' else '111111'
    assert client.post(f"{BASE}/{n['id']}/verify", headers=headers('bob'),
                       json={'challenge_id': c['challenge_id'], 'code': wrong}).status_code == 400
    ok = client.post(f"{BASE}/{n['id']}/verify", headers=headers('bob'),
                     json={'challenge_id': c['challenge_id'], 'code': c['test_code']})
    assert ok.status_code == 200, ok.text
    numbers = {x['masked']: x for x in ok.json()['numbers']}
    assert numbers['671 •• •• 89']['verified'] and numbers['671 •• •• 89']['receive_default']
    assert numbers['690 •• •• 56']['pay_default'] and not numbers['690 •• •• 56']['receive_default']
    # Receiving now goes to the verified MTN number, and counts as current.
    dest = client.get('/api/v1/me/receiving-destination', headers=headers('bob')).json()['destination']
    assert dest['method'] == 'MTN' and dest['identity_current'] is True
    # A used code never works twice.
    assert client.post(f"{BASE}/{n['id']}/verify", headers=headers('bob'),
                       json={'challenge_id': c['challenge_id'], 'code': c['test_code']}).status_code == 400


def test_codes_are_never_shown_without_the_test_switch(client):
    bind_phone(client)
    r = add(client, '671234589')
    assert 'test_code' not in r.json()['challenge']


def test_at_most_three_numbers_and_removal(client):
    bind_phone(client)
    for p in ('690123456', '671234589', '699876512'):
        assert add(client, p).status_code == 200
    assert add(client, '652000000').status_code == 409
    first = add(client, '690123456').json()['number']  # re-adding the same number is fine
    removed = client.post(f"{BASE}/{first['id']}/remove", headers=headers('bob')).json()
    assert len(removed['numbers']) == 2
    assert add(client, '652000000').status_code == 200


def test_defaults_only_on_verified_numbers(client):
    bind_phone(client)
    add(client, '690123456')
    other = add(client, '671234589').json()['number']
    assert client.post(f"{BASE}/{other['id']}/defaults", headers=headers('bob'),
                       json={'pay_default': True}).status_code == 409


def test_change_sign_in_number(client, monkeypatch):
    monkeypatch.setenv('SENDOH_SHOW_TEST_CODES', '1')
    bind_phone(client)
    bind_phone(client, 'eve', '+237690222333')
    taken = client.post('/api/v1/me/sign-in-number/code', headers=headers('bob'), json={'phone': '690222333'})
    assert taken.status_code == 409
    c = client.post('/api/v1/me/sign-in-number/code', headers=headers('bob'), json={'phone': '677000111'}).json()
    r = client.post('/api/v1/me/sign-in-number/verify', headers=headers('bob'),
                    json={'challenge_id': c['challenge_id'], 'code': c['test_code']})
    assert r.status_code == 200, r.text
    assert r.json()['sign_in_masked'] == '+237 677 •• •• 11'
    with client.app.state.sessions() as db:
        bob = db.scalar(select(User).where(User.username == 'bob'))
        assert db.scalar(select(PhoneIdentity.phone).where(PhoneIdentity.user_id == bob.id)) == '+237677000111'


def test_add_sign_in_number_without_typing_it(client):
    bind_phone(client)
    r = client.post(BASE, headers=headers('bob'), json={'sign_in_number': True})
    assert r.status_code == 200, r.text
    assert r.json()['number']['is_sign_in_number'] and r.json()['number']['verified']
    assert r.json()['number']['phone'] == '690123456'
