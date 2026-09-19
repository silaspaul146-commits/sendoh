import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Integer, BigInteger, DateTime, ForeignKey, CheckConstraint, UniqueConstraint, JSON
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def uid(): return str(uuid.uuid4())
def now(): return datetime.now(timezone.utc)

class Base(DeclarativeBase): pass

class User(Base):
    __tablename__ = 'users'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    display_name: Mapped[str] = mapped_column(String(120))
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)

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
    __table_args__ = (CheckConstraint('expected_amount IS NULL OR expected_amount > 0'),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    collection_id: Mapped[str] = mapped_column(ForeignKey('collections.id'), index=True)
    name: Mapped[str] = mapped_column(String(120))
    expected_amount: Mapped[int | None] = mapped_column(BigInteger)

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
