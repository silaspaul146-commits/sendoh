"""FCM HTTP v1 sender and restart-safe, at-least-once delivery worker."""
import asyncio
import json
import logging
import os
import re
import time
import uuid
from contextlib import asynccontextmanager
import httpx
from sqlalchemy import select, update, or_, and_
from .models import PushDelivery, PushDevice, Notification, Participant, RefreshSession

log = logging.getLogger('sendoh.push')

class SendFailure(Exception):
    def __init__(self, code, permanent=False, invalid_token=False):
        self.code, self.permanent, self.invalid_token = code, permanent, invalid_token
        super().__init__(code)

class FCMSender:
    def __init__(self, info):
        from google.oauth2 import service_account
        from google.auth.transport.requests import Request
        project = info.get('project_id', '')
        if not re.fullmatch(r'[a-z][a-z0-9-]{4,62}', project):
            raise RuntimeError('Invalid Firebase project ID.')
        if info.get('token_uri') != 'https://oauth2.googleapis.com/token':
            raise RuntimeError('Use an unmodified Firebase service-account key.')
        self.credentials = service_account.Credentials.from_service_account_info(info,
            scopes=['https://www.googleapis.com/auth/firebase.messaging'])
        self.transport = Request()
        self.url = f'https://fcm.googleapis.com/v1/projects/{project}/messages:send'

    def send(self, token, notification_id):
        try:
            if not self.credentials.valid:
                # Limit OAuth transport waits as well as the FCM request.
                self.credentials.refresh(lambda *a, **k: self.transport(*a, **{**k, 'timeout': 15}))
            response = httpx.post(self.url, headers={
                'Authorization': 'Bearer ' + self.credentials.token}, timeout=15,
                json={'message': {
                    'token': token,
                    'notification': {'title': 'Sendoh', 'body': 'You have a new update. Open Sendoh to view it.'},
                    'data': {'notification_id': notification_id},
                    'android': {'priority': 'high', 'ttl': '3600s',
                        'notification': {'tag': notification_id}},
                    'apns': {'headers': {'apns-collapse-id': notification_id,
                        'apns-expiration': str(int(time.time()) + 3600)},
                        'payload': {'aps': {'sound': 'default'}}},
                }})
        except Exception:
            # Never log device tokens, provider responses, or private keys.
            raise SendFailure('TRANSPORT_ERROR') from None
        if response.status_code < 300:
            return
        try:
            details = response.json().get('error', {}).get('details', [])
            codes = {d.get('errorCode') for d in details if isinstance(d, dict)}
        except (ValueError, AttributeError, TypeError):
            codes = set()
        if 'UNREGISTERED' in codes:
            raise SendFailure('UNREGISTERED', permanent=True, invalid_token=True)
        if response.status_code == 429 or response.status_code >= 500:
            raise SendFailure('PROVIDER_RETRY')
        if response.status_code in (401, 403):
            raise SendFailure('PROVIDER_AUTH')
        raise SendFailure('PROVIDER_REJECTED', permanent=True)

def configured_sender():
    if os.getenv('SENDOH_PUSH_ENABLED', '0') != '1':
        return None
    raw = os.getenv('FIREBASE_SERVICE_ACCOUNT_JSON', '')
    try:
        info = json.loads(raw)
        return FCMSender(info)
    except Exception:
        raise RuntimeError('Push is enabled but FIREBASE_SERVICE_ACCOUNT_JSON is missing or invalid.') from None

def session_live(db, device, environment, now):
    if environment == 'development' and device.family_id == 'dev:' + device.user_id:
        return True
    return db.scalar(select(RefreshSession.token_hash).where(
        RefreshSession.user_id == device.user_id, RefreshSession.family_id == device.family_id,
        RefreshSession.consumed == 0, RefreshSession.expires_at > now).limit(1)) is not None

def process_one(sessions, sender, environment):
    now = int(time.time())
    owner = str(uuid.uuid4())
    with sessions() as db:
        eligible = or_(and_(PushDelivery.state == 'PENDING', PushDelivery.due_at <= now),
                       and_(PushDelivery.state == 'SENDING', PushDelivery.lease_until <= now))
        job_id = db.scalar(select(PushDelivery.id).where(eligible)
                           .order_by(PushDelivery.due_at).limit(1))
        if not job_id:
            return False
        claimed = db.execute(update(PushDelivery).where(PushDelivery.id == job_id, eligible)
            .values(state='SENDING', lease_owner=owner, lease_until=now + 120,
                    attempts=PushDelivery.attempts + 1))
        if claimed.rowcount != 1:
            db.rollback()
            return True
        db.commit()
        job = db.get(PushDelivery, job_id)
        device = db.get(PushDevice, job.device_id)
        notification = db.get(Notification, job.notification_id)
        valid = bool(device and notification and device.active and device.expires_at > now and
            device.user_id == notification.user_id and device.token_hash == job.token_hash and
            device.family_id == job.family_id and not notification.read_at and
            notification.created_at > now - 86400 and session_live(db, device, environment, now))
        if valid and notification.kind == 'INVITED':
            p = db.get(Participant, notification.participant_id)
            valid = bool(p and p.invitation_version == notification.invitation_version and
                         p.invitation_state == 'PENDING' and (p.expires_at or 0) > now)
        state, code = ('SKIPPED', 'NO_LONGER_ELIGIBLE') if not valid else ('SENT', None)
        invalidate = False
        if valid:
            try:
                sender.send(device.token, notification.id)
            except SendFailure as exc:
                code, invalidate = exc.code, exc.invalid_token
                state = 'DEAD' if exc.permanent or job.attempts >= 6 else 'PENDING'
            except Exception:
                code = 'UNEXPECTED_SEND_ERROR'
                state = 'DEAD' if job.attempts >= 6 else 'PENDING'
        # Lease ownership protects a worker whose lease expired mid-request.
        result = db.execute(update(PushDelivery).where(PushDelivery.id == job_id,
            PushDelivery.lease_owner == owner).values(state=state, last_code=code,
                due_at=int(time.time()) + min(3600, 60 * 2 ** min(job.attempts, 6)),
                lease_until=0, lease_owner=None))
        if result.rowcount == 1 and invalidate:
            db.execute(update(PushDevice).where(PushDevice.id == job.device_id,
                PushDevice.token_hash == job.token_hash, PushDevice.family_id == job.family_id).values(active=0))
        db.commit()
        if code and state != 'SKIPPED':
            log.warning('Push delivery %s: %s (%s)', job_id, code, state)
        return True

def lifespan_for(sessions, sender, environment):
    @asynccontextmanager
    async def lifespan(app):
        stop = asyncio.Event()
        async def loop():
            while not stop.is_set():
                try:
                    worked = await asyncio.to_thread(process_one, sessions, sender, environment)
                except Exception:
                    log.warning('Push queue temporarily unavailable; will retry.')
                    worked = False
                try:
                    await asyncio.wait_for(stop.wait(), timeout=1 if worked else 10)
                except asyncio.TimeoutError:
                    pass
        task = asyncio.create_task(loop()) if sender else None
        try:
            yield
        finally:
            stop.set()
            if task:
                await task
    return lifespan
