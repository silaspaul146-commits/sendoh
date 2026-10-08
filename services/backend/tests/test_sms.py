from dataclasses import replace
from types import SimpleNamespace
import pytest
from app.config import load_settings
from app.otp import deliver_otp

@pytest.mark.parametrize('group,accepted', [(1, True), (3, True), (2, False), (5, False), (4, False)])
def test_sms_provider_acceptance(monkeypatch, group, accepted):
    monkeypatch.setenv('INFOBIP_BASE_URL', 'https://example.api.infobip.com')
    monkeypatch.setenv('INFOBIP_API_KEY', 'test-key')
    monkeypatch.setenv('INFOBIP_SENDER', 'ServiceSMS')
    settings = replace(load_settings('sqlite://'), otp_provider='infobip')
    sent = []
    def post(url, **kwargs):
        sent.append(kwargs)
        return SimpleNamespace(raise_for_status=lambda: None,
            json=lambda: {'messages': [{'status': {'groupId': group}}]})
    monkeypatch.setattr('app.otp.httpx.post', post)
    if accepted:
        assert deliver_otp(settings, '+237670123456', 'challenge', '123456') == 'sms'
    else:
        with pytest.raises(RuntimeError):
            deliver_otp(settings, '+237670123456', 'challenge', '123456')
    assert sent[0]['json']['messages'][0]['destinations'] == [{'to':'237670123456'}]
