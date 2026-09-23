import pytest

from app.config import load_settings, normalize_database_url


def test_normalizes_neon_postgres_url():
    assert normalize_database_url('postgresql://u:p@example/db?sslmode=require') == (
        'postgresql+psycopg://u:p@example/db?sslmode=require'
    )


def test_staging_rejects_sqlite(monkeypatch):
    monkeypatch.setenv('SENDOH_ENV', 'staging')
    monkeypatch.setenv('PUBLIC_WEB_URL', 'https://sendoh.example')
    monkeypatch.setenv('OTP_PROVIDER', 'log')
    monkeypatch.setenv('ALLOW_STAGING_LOG_OTP', '1')
    with pytest.raises(RuntimeError, match='PostgreSQL'):
        load_settings('sqlite:///./sendoh.db')


def test_production_rejects_logged_otp(monkeypatch):
    monkeypatch.setenv('SENDOH_ENV', 'production')
    monkeypatch.setenv('PUBLIC_WEB_URL', 'https://sendoh.example')
    monkeypatch.setenv('OTP_PROVIDER', 'log')
    with pytest.raises(RuntimeError, match='Production requires'):
        load_settings('postgresql+psycopg://u:p@example/db')
