"""Restricted, one-per-application sandbox payout diagnostic.

Not a customer transfer API. Never invoked by startup/build or reconciliation
workers. A committed reservation grants exactly one dispatch opportunity; a
crash/timeout never grants another. Provider evidence is not a delivery receipt.
"""
import hashlib
import hmac
import os
import re
import time
import uuid
from typing import Literal

from fastapi import APIRouter, Header, HTTPException, Request
from pydantic import BaseModel, ConfigDict
from sqlalchemy import BigInteger, JSON, String, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, mapped_column
from .models import Base
from .providers.mesomb import local_phone, safe_amount_evidence


class SandboxPayoutProbe(Base):
    __tablename__ = 'sandbox_payout_probes'
    application_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    reference: Mapped[str] = mapped_column(String(36), unique=True, nullable=False)
    created_at: Mapped[int] = mapped_column(BigInteger, nullable=False)
    updated_at: Mapped[int] = mapped_column(BigInteger, nullable=False)
    next_check_at: Mapped[int] = mapped_column(BigInteger, nullable=False)
    lease_owner: Mapped[str | None] = mapped_column(String(36))
    lease_until: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    submission_result: Mapped[str] = mapped_column(String(48), nullable=False)
    lookup_result: Mapped[str] = mapped_column(String(48), nullable=False)
    evidence: Mapped[dict | None] = mapped_column(JSON)


class Confirm(BaseModel):
    model_config = ConfigDict(extra='forbid')
    confirm: Literal['RUN_SANDBOX_PAYOUT']


def safe_error(exc):
    value = str(exc)
    if re.fullmatch(r'HTTP_STATUS:[1-5][0-9]{2}', value):
        return value
    if value in ('TRANSPORT_OR_JSON_ERROR', 'LOOKUP_SHAPE_INVALID'):
        return value
    return 'UNRESOLVED_ERROR'


def machine_word(value):
    return value if isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9_-]{1,40}', value) else 'UNKNOWN'


def evidence(rows):
    if len(rows) != 1:
        return dict(matches=len(rows))
    row = rows[0]
    try:
        matches_receiver = local_phone(row.get('b_party')) == '600000001'
    except (ValueError, TypeError):
        matches_receiver = False
    return dict(matches=1, provider_status=machine_word(row.get('status')),
        transaction_type=machine_word(row.get('type')), amounts=safe_amount_evidence(row),
        currency=machine_word(row.get('currency')), country=machine_word(row.get('country')),
        service=machine_word(row.get('service')), receiver_matches=matches_receiver)


def view(p):
    return dict(reference=p.reference, mode='SANDBOX', purpose='PAYOUT_DIAGNOSTIC',
        requested_amount=1000, currency='XAF', service='MTN', receiver='600000001',
        submission_result=p.submission_result, lookup_result=p.lookup_result,
        provider_evidence=p.evidence, delivery_confirmed=False,
        created_at=p.created_at, updated_at=p.updated_at, next_check_at=p.next_check_at)


def router(sessions, config, environment):
    routes = APIRouter(prefix='/api/v1/internal/sandbox-payout', include_in_schema=False)

    def authorize(token):
        expected = os.getenv('SENDOH_SANDBOX_DIAGNOSTIC_TOKEN', '')
        if (config is None or environment == 'production' or
            os.getenv('SENDOH_MESOMB_MODE') != 'sandbox' or
            os.getenv('MESOMB_SANDBOX_CONFIRMED') != '1' or
            not re.fullmatch(r'[a-f0-9]{64}', expected)):
            raise HTTPException(404, 'Not found.')
        if not token or len(token) > 256 or not hmac.compare_digest(
                hashlib.sha256(token.encode()).digest(), hashlib.sha256(expected.encode()).digest()):
            raise HTTPException(403, 'Diagnostic access denied.')

    @routes.get('')
    def detail(x_sendoh_diagnostic_token: str | None = Header(default=None)):
        authorize(x_sendoh_diagnostic_token)
        with sessions() as db:
            p = db.get(SandboxPayoutProbe, config.application_hash)
            if not p:
                raise HTTPException(404, 'No server payout diagnostic has been created.')
            return view(p)

    @routes.post('')
    def create(data: Confirm, request: Request,
               x_sendoh_diagnostic_token: str | None = Header(default=None)):
        authorize(x_sendoh_diagnostic_token)
        now = int(time.time())
        with sessions() as db:
            existing = db.get(SandboxPayoutProbe, config.application_hash)
            if existing:
                return view(existing)
            p = SandboxPayoutProbe(application_hash=config.application_hash,
                reference=str(uuid.uuid4()), created_at=now, updated_at=now,
                submission_result='RESERVED_OUTCOME_UNKNOWN', lookup_result='NOT_CHECKED',
                next_check_at=now + 30, lease_until=0)
            db.add(p)
            try:
                db.commit()
            except IntegrityError:
                db.rollback()
                existing = db.get(SandboxPayoutProbe, config.application_hash)
                if existing:
                    return view(existing)
                raise HTTPException(409, 'Diagnostic reservation conflict.')
            reference = p.reference
        # Only the process which committed the new row may dispatch. No retry.
        try:
            request.app.state.mesomb_client.deposit(external_id=reference, amount=1000,
                receiver='600000001', service='MTN')
            result = 'RESPONSE_RECEIVED_UNVERIFIED'
        except Exception as exc:
            result = safe_error(exc)
        with sessions() as db:
            p = db.get(SandboxPayoutProbe, config.application_hash)
            p.submission_result = result
            p.updated_at = int(time.time())
            p.next_check_at = p.updated_at
            db.commit()
            return view(p)

    @routes.post('/refresh')
    def refresh(request: Request, x_sendoh_diagnostic_token: str | None = Header(default=None)):
        authorize(x_sendoh_diagnostic_token)
        owner = str(uuid.uuid4())
        now = int(time.time())
        with sessions() as db:
            p = db.get(SandboxPayoutProbe, config.application_hash)
            if not p:
                raise HTTPException(404, 'No server payout diagnostic has been created.')
            reference = p.reference
            changed = db.execute(update(SandboxPayoutProbe).where(
                SandboxPayoutProbe.application_hash == config.application_hash,
                SandboxPayoutProbe.lease_until <= now,
                SandboxPayoutProbe.next_check_at <= now).values(lease_owner=owner, lease_until=now+60))
            db.commit()
            if changed.rowcount != 1:
                db.refresh(p)
                return view(p)
        details = None
        try:
            rows = request.app.state.mesomb_client.lookup(reference)
            details = evidence(rows)
            result = 'EVIDENCE_RETRIEVED' if len(rows) == 1 else ('NO_MATCH_YET' if not rows else 'MULTIPLE_MATCHES')
        except Exception as exc:
            result = safe_error(exc)
        with sessions() as db:
            p = db.scalar(select(SandboxPayoutProbe).where(
                SandboxPayoutProbe.application_hash == config.application_hash,
                SandboxPayoutProbe.lease_owner == owner).with_for_update())
            if p is not None:
                p.lookup_result = result
                if details is not None:
                    p.evidence = details
                p.updated_at = int(time.time())
                p.next_check_at = p.updated_at+10
                p.lease_until = 0
                p.lease_owner = None
                db.commit()
            else:
                p = db.get(SandboxPayoutProbe, config.application_hash)
            return view(p)
    return routes
