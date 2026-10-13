import time
from dataclasses import replace

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.auth import router
from app.config import load_settings
from app.models import Base, User, PhoneIdentity, PushDevice, RefreshSession


def test_push_otp_only_to_existing_live_bound_devices(tmp_path, monkeypatch):
    monkeypatch.setenv("SENDOH_ENV", "development")
    monkeypatch.setenv("OTP_PROVIDER", "local")
    monkeypatch.setenv("SENDOH_STAGING_PUSH_OTP", "1")

    engine = create_engine(
        f"sqlite:///{tmp_path}/otp.db",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(engine)
    sessions = sessionmaker(engine)
    now = int(time.time())

    with sessions() as db:
        db.add(
            User(
                id="member",
                display_name="Member",
                token_hash="hash",
            )
        )
        db.flush()
        db.add(
            PhoneIdentity(
                phone="+237690123456",
                user_id="member",
            )
        )
        db.add(
            RefreshSession(
                token_hash="refresh",
                user_id="member",
                family_id="family",
                expires_at=now + 1000,
                consumed=0,
            )
        )
        db.add(
            PushDevice(
                user_id="member",
                family_id="family",
                token="trusted-device",
                token_hash="devicehash",
                platform="android",
                active=1,
                updated_at=now,
                expires_at=now + 1000,
            )
        )
        db.commit()

    sent = []
    fallback = []

    class Sender:
        def send(self, token, challenge, *, otp):
            sent.append((token, challenge, otp))

    def database():
        with sessions() as db:
            yield db

    def log_otp(settings, phone, challenge_id, code):
        fallback.append((phone, challenge_id, code))
        return "staging-log"

    monkeypatch.setattr("app.auth.deliver_otp", log_otp)

    settings = replace(
        load_settings("sqlite://"),
        environment="staging",
        otp_provider="log",
    )
    app = FastAPI()
    app.include_router(
        router(database, lambda: None, lambda: None, settings, Sender())
    )

    try:
        with TestClient(app) as client:
            # A caller cannot supply an arbitrary push destination.
            rejected = client.post(
                "/api/v1/auth/code",
                json={
                    "phone": "+237690123456",
                    "token": "attacker-device",
                },
            )
            assert rejected.status_code == 422
            assert sent == []
            assert fallback == []

            response = client.post(
                "/api/v1/auth/code",
                json={"phone": "+237690123456"},
            )
            assert response.status_code == 200
            data = response.json()
            assert data["delivery"] == "staging-push"

            # TestClient waits for background tasks before returning.
            assert len(sent) == 1
            token, challenge_id, code = sent[0]
            assert token == "trusted-device"
            assert challenge_id == data["challenge_id"]
            assert len(code) == 6
            assert code.isdigit()

            # The same code remains available in staging logs.
            assert fallback == [
                ("+237690123456", challenge_id, code),
            ]

            # A new phone has no trusted device, so only logging is used.
            new_response = client.post(
                "/api/v1/auth/code",
                json={"phone": "+237690123457"},
            )
            assert new_response.status_code == 200
            new_data = new_response.json()
            assert new_data["delivery"] == "staging-log"

            assert len(sent) == 1
            assert len(fallback) == 2
            assert fallback[1][0] == "+237690123457"
            assert fallback[1][1] == new_data["challenge_id"]
            assert len(fallback[1][2]) == 6
            assert fallback[1][2].isdigit()
    finally:
        engine.dispose()