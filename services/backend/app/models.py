import uuid
from decimal import Decimal
from datetime import datetime, timezone
from sqlalchemy import Numeric, String, Integer, BigInteger, DateTime, ForeignKey, CheckConstraint, UniqueConstraint, JSON, Text, Index, text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def uid(): return str(uuid.uuid4())
def now(): return datetime.now(timezone.utc)

class Base(DeclarativeBase): pass

class User(Base):
    __tablename__ = 'users'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    display_name: Mapped[str] = mapped_column(String(120))
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    username: Mapped[str | None] = mapped_column(String(24), unique=True)
    avatar: Mapped[str | None] = mapped_column(Text)

class Collection(Base):
    __tablename__ = 'collections'
    __table_args__ = (
        CheckConstraint('target_amount IS NULL OR target_amount > 0'),
        CheckConstraint('expected_amount IS NULL OR expected_amount > 0'),
        CheckConstraint("currency = 'XAF'"),
        CheckConstraint("status IN ('DRAFT', 'ACTIVE')"),
        CheckConstraint("mode IN ('ANY_AMOUNT', 'EXPECTED_TOTAL', 'MINIMUM_TOTAL')"),
        CheckConstraint("(mode = 'ANY_AMOUNT' AND expected_amount IS NULL) OR (mode != 'ANY_AMOUNT' AND expected_amount IS NOT NULL)"),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    organizer_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    public_token: Mapped[str] = mapped_column(String(80), unique=True)
    name: Mapped[str] = mapped_column(String(120))
    description: Mapped[str] = mapped_column(String(2000), default='')
    currency: Mapped[str] = mapped_column(String(3), default='XAF')
    target_amount: Mapped[int | None] = mapped_column(BigInteger)
    deadline_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    mode: Mapped[str] = mapped_column(String(24))
    expected_amount: Mapped[int | None] = mapped_column(BigInteger)
    status: Mapped[str] = mapped_column(String(16), default='DRAFT')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

class Participant(Base):
    __tablename__ = 'participants'
    __table_args__ = (
        CheckConstraint('expected_amount IS NULL OR expected_amount > 0'),
        CheckConstraint("invitation_state IN ('UNVERIFIED','PENDING','ACCEPTED','DECLINED','CANCELLED')", name='ck_participant_invitation_state'),
        UniqueConstraint('collection_id', 'user_id', name='uq_participant_member'),
        UniqueConstraint('collection_id', 'invited_user_id', name='uq_participant_invited_user'),
        UniqueConstraint('collection_id', 'invited_phone', name='uq_participant_invited_phone'),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    collection_id: Mapped[str] = mapped_column(ForeignKey('collections.id'), index=True)
    name: Mapped[str] = mapped_column(String(120))
    expected_amount: Mapped[int | None] = mapped_column(BigInteger)
    user_id: Mapped[str | None] = mapped_column(ForeignKey('users.id'), index=True)
    invited_user_id: Mapped[str | None] = mapped_column(ForeignKey('users.id'), index=True)
    invited_phone: Mapped[str | None] = mapped_column(String(16), index=True)
    invitation_state: Mapped[str] = mapped_column(String(16), default='UNVERIFIED', server_default='UNVERIFIED')
    invited_at: Mapped[int | None] = mapped_column(BigInteger)
    expires_at: Mapped[int | None] = mapped_column(BigInteger)

    invitation_version: Mapped[int] = mapped_column(Integer, default=1, server_default='1')

class Notification(Base):
    __tablename__ = 'notifications'
    order_id: Mapped[str | None] = mapped_column(String(36))
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    collection_id: Mapped[str | None] = mapped_column(ForeignKey('collections.id'))
    participant_id: Mapped[str | None] = mapped_column(ForeignKey('participants.id'))
    invitation_version: Mapped[int | None] = mapped_column(Integer)
    request_id: Mapped[str | None] = mapped_column(String(36))
    kind: Mapped[str] = mapped_column(String(32))
    event_key: Mapped[str] = mapped_column(String(160), unique=True)
    created_at: Mapped[int] = mapped_column(BigInteger)
    read_at: Mapped[int | None] = mapped_column(BigInteger)

class PushDevice(Base):
    __tablename__ = 'push_devices'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    family_id: Mapped[str] = mapped_column(String(80), index=True)
    token: Mapped[str] = mapped_column(Text)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    platform: Mapped[str] = mapped_column(String(8))
    active: Mapped[int] = mapped_column(Integer, default=1)
    updated_at: Mapped[int] = mapped_column(BigInteger)
    expires_at: Mapped[int] = mapped_column(BigInteger)

class PushDelivery(Base):
    __tablename__ = 'push_deliveries'
    __table_args__ = (UniqueConstraint('notification_id', 'device_id', name='uq_notification_device'),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    notification_id: Mapped[str] = mapped_column(ForeignKey('notifications.id'))
    device_id: Mapped[str] = mapped_column(ForeignKey('push_devices.id'))
    token_hash: Mapped[str] = mapped_column(String(64))
    family_id: Mapped[str] = mapped_column(String(80))
    state: Mapped[str] = mapped_column(String(12), default='PENDING')
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    due_at: Mapped[int] = mapped_column(BigInteger, index=True)
    lease_until: Mapped[int] = mapped_column(BigInteger, default=0)
    lease_owner: Mapped[str | None] = mapped_column(String(36))
    last_code: Mapped[str | None] = mapped_column(String(40))

class InvitationRate(Base):
    __tablename__ = 'invitation_rates'
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), primary_key=True)
    window_start: Mapped[int] = mapped_column(BigInteger)
    count: Mapped[int] = mapped_column(Integer)

class Activity(Base):
    __tablename__ = 'activity'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    organizer_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    collection_id: Mapped[str] = mapped_column(ForeignKey('collections.id'))
    message: Mapped[str] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

class Idempotency(Base):
    __tablename__ = 'idempotency'
    __table_args__ = (UniqueConstraint('actor_id', 'key', name='uq_actor_key'),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    actor_id: Mapped[str] = mapped_column(ForeignKey('users.id'))
    key: Mapped[str] = mapped_column(String(120))
    fingerprint: Mapped[str] = mapped_column(String(64))
    response: Mapped[dict | None] = mapped_column(JSON)

class PhoneIdentity(Base):
    __tablename__ = 'phone_identities'
    phone: Mapped[str] = mapped_column(String(16), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), unique=True)

class OtpChallenge(Base):
    __tablename__ = 'otp_challenges'
    phone: Mapped[str] = mapped_column(String(16), primary_key=True)
    challenge_id: Mapped[str] = mapped_column(String(36), unique=True)
    code_hash: Mapped[str] = mapped_column(String(64))
    sent_at: Mapped[int] = mapped_column(BigInteger)
    expires_at: Mapped[int] = mapped_column(BigInteger)
    attempts: Mapped[int] = mapped_column(Integer, default=0)

class AuthSession(Base):
    __tablename__ = 'auth_sessions'
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    expires_at: Mapped[int] = mapped_column(BigInteger)
    family_id: Mapped[str | None] = mapped_column(String(36), index=True)

class RefreshSession(Base):
    __tablename__ = 'refresh_sessions'
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    family_id: Mapped[str] = mapped_column(String(36), index=True)
    expires_at: Mapped[int] = mapped_column(BigInteger)
    consumed: Mapped[int] = mapped_column(Integer, default=0)

class TestPayment(Base):
    """Sandbox-only ledger, deliberately separate from future real payments."""
    __tablename__ = 'test_payments'
    __table_args__ = (
        UniqueConstraint('payer_id', 'request_key', name='uq_test_payment_request'),
        CheckConstraint('amount > 0 AND amount <= 1000000000000'),
        CheckConstraint("status IN ('PENDING','SUCCEEDED','FAILED','CANCELLED')"),
        CheckConstraint("method IN ('MTN','ORANGE')"),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    collection_id: Mapped[str] = mapped_column(ForeignKey('collections.id'), index=True)
    participant_id: Mapped[str] = mapped_column(ForeignKey('participants.id'), index=True)
    payer_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    payer_name: Mapped[str] = mapped_column(String(120))
    collection_name: Mapped[str] = mapped_column(String(120))
    request_key: Mapped[str] = mapped_column(String(120))
    fingerprint: Mapped[str] = mapped_column(String(64))
    amount: Mapped[int] = mapped_column(BigInteger)
    method: Mapped[str] = mapped_column(String(8))
    note: Mapped[str] = mapped_column(String(200), default='')
    status: Mapped[str] = mapped_column(String(12), default='PENDING')
    created_at: Mapped[int] = mapped_column(BigInteger)
    completed_at: Mapped[int | None] = mapped_column(BigInteger)

class MoneyRequest(Base):
    __tablename__ = 'money_requests'
    __table_args__ = (
        UniqueConstraint('requester_id', 'request_key', name='uq_money_request_key'),
        CheckConstraint('amount > 0 AND amount <= 1000000000'),
        CheckConstraint('requester_id != recipient_id'),
        CheckConstraint("status IN ('PENDING','DECLINED','CANCELLED')"),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    requester_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    recipient_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    amount: Mapped[int] = mapped_column(BigInteger)
    reason: Mapped[str] = mapped_column(String(140))
    expires_at: Mapped[int | None] = mapped_column(BigInteger)
    status: Mapped[str] = mapped_column(String(12), default='PENDING')
    request_key: Mapped[str] = mapped_column(String(120))
    fingerprint: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[int] = mapped_column(BigInteger)


class ProviderPayment(Base):
    __tablename__ = 'provider_payments'
    __table_args__ = (
        UniqueConstraint('payer_id', 'request_key', name='uq_provider_payment_request'),
        UniqueConstraint('application_hash', 'provider_id', name='uq_provider_transaction'),
        Index('uq_pending_provider_collection', 'payer_id', 'collection_id', unique=True,
              sqlite_where=text("status = 'PENDING'"), postgresql_where=text("status = 'PENDING'")),
        CheckConstraint("mode = 'SANDBOX'"),
        CheckConstraint("status IN ('PENDING','SUCCEEDED','FAILED','REFUNDED')"),
        CheckConstraint('amount > 0 AND amount <= 1000000000'),
        CheckConstraint("method IN ('MTN','ORANGE')"),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    collection_id: Mapped[str] = mapped_column(ForeignKey('collections.id'), index=True)
    participant_id: Mapped[str] = mapped_column(ForeignKey('participants.id'))
    payer_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    beneficiary_id: Mapped[str] = mapped_column(ForeignKey('users.id'))
    request_key: Mapped[str] = mapped_column(String(120))
    fingerprint: Mapped[str] = mapped_column(String(64))
    application_hash: Mapped[str] = mapped_column(String(64))
    mode: Mapped[str] = mapped_column(String(12), default='SANDBOX')
    amount: Mapped[int] = mapped_column(BigInteger)
    method: Mapped[str] = mapped_column(String(8))
    payer_phone: Mapped[str] = mapped_column(String(16))
    status: Mapped[str] = mapped_column(String(12), default='PENDING')
    provider_id: Mapped[str | None] = mapped_column(String(120))
    provider_status: Mapped[str | None] = mapped_column(String(40))
    confirmed_gross: Mapped[Decimal | None] = mapped_column(Numeric(20, 6))
    confirmed_provider_fee: Mapped[Decimal | None] = mapped_column(Numeric(20, 6))
    confirmed_net: Mapped[Decimal | None] = mapped_column(Numeric(20, 6))
    accounting_verified_at: Mapped[int | None] = mapped_column(BigInteger)

    review_reason: Mapped[str | None] = mapped_column(String(80))
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    next_check_at: Mapped[int] = mapped_column(BigInteger, index=True)
    lease_until: Mapped[int] = mapped_column(BigInteger, default=0)
    lease_owner: Mapped[str | None] = mapped_column(String(36))
    created_at: Mapped[int] = mapped_column(BigInteger)
    updated_at: Mapped[int] = mapped_column(BigInteger)


class ProviderPaymentEvent(Base):
    __tablename__ = 'provider_payment_events'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    payment_id: Mapped[str] = mapped_column(ForeignKey('provider_payments.id'), index=True)
    status: Mapped[str] = mapped_column(String(12))
    created_at: Mapped[int] = mapped_column(BigInteger)
    __table_args__ = (UniqueConstraint('payment_id','status',name='uq_provider_payment_effect'),)


class MeSombWebhook(Base):
    __tablename__ = 'mesomb_webhooks'
    event_id: Mapped[str] = mapped_column(String(160), primary_key=True)
    body_hash: Mapped[str] = mapped_column(String(64))
    event_type: Mapped[str] = mapped_column(String(120))
    received_at: Mapped[int] = mapped_column(BigInteger)


class ReceivingDestination(Base):
    """Immutable recipient consent versions; never a provider verification claim."""
    __tablename__ = 'receiving_destinations'
    __table_args__ = (
        UniqueConstraint('user_id', 'version', name='uq_receiving_destination_version'),
        CheckConstraint('version > 0'),
        CheckConstraint("method IN ('MTN','ORANGE')"),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    version: Mapped[int] = mapped_column(Integer)
    phone: Mapped[str] = mapped_column(String(16))
    method: Mapped[str] = mapped_column(String(8))
    created_at: Mapped[int] = mapped_column(BigInteger)


class PersonQuote(Base):
    __tablename__ = 'person_quotes'
    __table_args__ = (CheckConstraint('expires_at > created_at'),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    payer_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    beneficiary_id: Mapped[str] = mapped_column(ForeignKey('users.id'))
    request_id: Mapped[str | None] = mapped_column(ForeignKey('money_requests.id'))
    destination_id: Mapped[str] = mapped_column(ForeignKey('receiving_destinations.id'))
    application_hash: Mapped[str] = mapped_column(String(64))
    policy_hash: Mapped[str] = mapped_column(String(64))
    policy: Mapped[dict] = mapped_column(JSON)
    amounts: Mapped[dict] = mapped_column(JSON)
    payer_phone: Mapped[str] = mapped_column(String(16))
    payer_method: Mapped[str] = mapped_column(String(8))
    created_at: Mapped[int] = mapped_column(BigInteger)
    expires_at: Mapped[int] = mapped_column(BigInteger)


class PersonOrder(Base):
    __tablename__ = 'person_orders'
    __table_args__ = (
        UniqueConstraint('payer_id', 'request_key', name='uq_person_order_key'),
        UniqueConstraint('quote_id', name='uq_person_order_quote'),
        Index('uq_ready_order_request', 'request_id', unique=True,
              sqlite_where=text("status = 'READY'"), postgresql_where=text("status = 'READY'")),
        CheckConstraint("status IN ('READY','CANCELLED','EXPIRED')"),
        CheckConstraint("collection_status = 'NOT_STARTED'"),
        CheckConstraint("delivery_status = 'NOT_STARTED'"),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    quote_id: Mapped[str] = mapped_column(ForeignKey('person_quotes.id'))
    payer_id: Mapped[str] = mapped_column(ForeignKey('users.id'), index=True)
    beneficiary_id: Mapped[str] = mapped_column(ForeignKey('users.id'))
    request_id: Mapped[str | None] = mapped_column(ForeignKey('money_requests.id'))
    request_key: Mapped[str] = mapped_column(String(120))
    status: Mapped[str] = mapped_column(String(16), default='READY')
    collection_status: Mapped[str] = mapped_column(String(16), default='NOT_STARTED')
    delivery_status: Mapped[str] = mapped_column(String(16), default='NOT_STARTED')
    created_at: Mapped[int] = mapped_column(BigInteger)
    expires_at: Mapped[int] = mapped_column(BigInteger)


class PersonExecution(Base):
    __tablename__ = 'person_executions'
    __table_args__ = (
        Index('uq_active_request_execution', 'request_id', unique=True,
              sqlite_where=text("state != 'FAILED'"), postgresql_where=text("state != 'FAILED'")),
        CheckConstraint("state IN ('COLLECTING','FUNDED','DELIVERING','SUCCEEDED','FAILED','REVIEW')"),
    )
    order_id: Mapped[str] = mapped_column(ForeignKey('person_orders.id'), primary_key=True)
    request_id: Mapped[str | None] = mapped_column(ForeignKey('money_requests.id'))
    application_hash: Mapped[str] = mapped_column(String(64))
    state: Mapped[str] = mapped_column(String(16), default='COLLECTING')
    reason: Mapped[str | None] = mapped_column(String(80))
    created_at: Mapped[int] = mapped_column(BigInteger)
    updated_at: Mapped[int] = mapped_column(BigInteger)


class PersonPaymentLeg(Base):
    __tablename__ = 'person_payment_legs'
    __table_args__ = (
        UniqueConstraint('order_id', 'kind', name='uq_person_order_leg'),
        CheckConstraint("kind IN ('COLLECT','DELIVER')"),
        CheckConstraint("status IN ('PENDING','SUCCEEDED','FAILED','REFUNDED')"),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    order_id: Mapped[str] = mapped_column(ForeignKey('person_executions.order_id'))
    application_hash: Mapped[str] = mapped_column(String(64))
    kind: Mapped[str] = mapped_column(String(8))
    amount: Mapped[int] = mapped_column(BigInteger)
    method: Mapped[str] = mapped_column(String(8))
    phone: Mapped[str] = mapped_column(String(16))
    status: Mapped[str] = mapped_column(String(16), default='PENDING')
    provider_id: Mapped[str | None] = mapped_column(String(120))
    net: Mapped[Decimal | None] = mapped_column(Numeric(20,6))
    fee: Mapped[Decimal | None] = mapped_column(Numeric(20,6))
    review_reason: Mapped[str | None] = mapped_column(String(80))
    lease_owner: Mapped[str | None] = mapped_column(String(36))
    lease_until: Mapped[int] = mapped_column(BigInteger, default=0)
    next_check_at: Mapped[int] = mapped_column(BigInteger, index=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[int] = mapped_column(BigInteger)


class ProviderReferenceClaim(Base):
    __tablename__ = 'provider_reference_claims'
    application_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    provider_id: Mapped[str] = mapped_column(String(120), primary_key=True)
    sendoh_reference: Mapped[str] = mapped_column(String(36))
