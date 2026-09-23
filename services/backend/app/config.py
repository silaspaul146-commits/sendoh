import os
from dataclasses import dataclass
from urllib.parse import urlparse


VALID_ENVIRONMENTS = {'development', 'staging', 'production'}
VALID_OTP_PROVIDERS = {'local', 'log', 'infobip'}


def _csv(name: str) -> tuple[str, ...]:
    return tuple(value.strip() for value in os.getenv(name, '').split(',') if value.strip())


def normalize_database_url(value: str) -> str:
    # Neon and Render show a standard PostgreSQL URL. Select the installed
    # psycopg v3 driver explicitly so SQLAlchemy does not look for psycopg2.
    if value.startswith('postgres://'):
        return 'postgresql+psycopg://' + value.removeprefix('postgres://')
    if value.startswith('postgresql://'):
        return 'postgresql+psycopg://' + value.removeprefix('postgresql://')
    return value


@dataclass(frozen=True)
class Settings:
    environment: str
    database_url: str
    public_web_url: str
    otp_provider: str
    cors_origins: tuple[str, ...]
    allowed_hosts: tuple[str, ...]


def load_settings(database_url: str | None = None) -> Settings:
    environment = os.getenv('SENDOH_ENV', 'development').strip().lower()
    if environment not in VALID_ENVIRONMENTS:
        raise RuntimeError('SENDOH_ENV must be development, staging, or production.')

    raw_database_url = database_url or os.getenv('DATABASE_URL', 'sqlite:///./sendoh.db')
    database = normalize_database_url(raw_database_url)
    public_web_url = os.getenv('PUBLIC_WEB_URL', 'http://localhost:3000').rstrip('/')
    otp_provider = os.getenv(
        'OTP_PROVIDER',
        'local' if environment == 'development' else 'log' if environment == 'staging' else '',
    ).strip().lower()

    if otp_provider not in VALID_OTP_PROVIDERS:
        raise RuntimeError('OTP_PROVIDER must be local, log, or infobip.')
    if environment != 'development' and database.startswith('sqlite'):
        raise RuntimeError('Staging and production require PostgreSQL; SQLite is local-only.')
    if environment != 'development' and urlparse(public_web_url).scheme != 'https':
        raise RuntimeError('PUBLIC_WEB_URL must use HTTPS outside development.')
    if environment == 'production' and otp_provider != 'infobip':
        raise RuntimeError('Production requires OTP_PROVIDER=infobip.')
    if environment == 'staging' and otp_provider == 'log' and os.getenv('ALLOW_STAGING_LOG_OTP') != '1':
        raise RuntimeError('Set ALLOW_STAGING_LOG_OTP=1 to acknowledge staging-only OTP logging.')
    if otp_provider == 'infobip':
        missing = [name for name in ('INFOBIP_BASE_URL', 'INFOBIP_API_KEY', 'INFOBIP_SENDER') if not os.getenv(name)]
        if missing:
            raise RuntimeError('Missing Infobip configuration: ' + ', '.join(missing))

    return Settings(
        environment=environment,
        database_url=database,
        public_web_url=public_web_url,
        otp_provider=otp_provider,
        cors_origins=_csv('CORS_ORIGINS'),
        allowed_hosts=_csv('ALLOWED_HOSTS'),
    )
