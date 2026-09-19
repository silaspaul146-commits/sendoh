"""Explicit local-only provisioning. Not an authentication or OTP implementation."""
import hashlib, os, secrets
from sqlalchemy.orm import Session
from .main import app
from .models import User
if os.getenv('SENDOH_ENV') != 'development':
    raise SystemExit('Set SENDOH_ENV=development to provision a local development identity.')
token=secrets.token_urlsafe(32)
with Session(app.state.engine) as db:
    db.add(User(display_name='Local organizer',token_hash=hashlib.sha256(token.encode()).hexdigest()))
    db.commit()
print('Local development token (store securely; never commit):')
print(token)
