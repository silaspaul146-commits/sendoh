import logging
import os
from pathlib import Path

import httpx

from .config import Settings


logger = logging.getLogger('sendoh.otp')


def otp_directory() -> Path:
    return Path(os.getenv('SENDOH_DEV_OTP_DIR', '.dev-otp'))


def deliver_otp(settings: Settings, phone: str, challenge_id: str, code: str) -> str:
    if settings.otp_provider == 'local':
        directory = otp_directory()
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        path = directory / challenge_id
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream:
            stream.write(code)
        return 'local-development'

    if settings.otp_provider == 'log':
        # Staging only. Render redacts configured secrets, but this value is not
        # a secret variable, so remove this mode before inviting public users.
        logger.warning('SENDOH_STAGING_OTP challenge=%s phone=%s code=%s', challenge_id, phone, code)
        return 'staging-log'

    base_url = os.environ['INFOBIP_BASE_URL'].rstrip('/')
    response = httpx.post(
        f'{base_url}/sms/3/messages',
        headers={
            'Authorization': f"App {os.environ['INFOBIP_API_KEY']}",
            'Accept': 'application/json',
            'Content-Type': 'application/json',
        },
        json={
            'messages': [{
                'sender': os.environ['INFOBIP_SENDER'],
                'destinations': [{'to': phone.removeprefix('+')}],
                'content': {'text': f'Your Sendoh verification code is {code}. It expires in 5 minutes.'},
            }]
        },
        timeout=10,
    )
    response.raise_for_status()
    messages = response.json().get('messages', [])
    if len(messages) != 1 or messages[0].get('status', {}).get('groupId') not in (1, 3):
        # HTTP 200 can still contain a rejected destination/sender result.
        raise RuntimeError('SMS provider did not accept this message.')
    return 'sms'
