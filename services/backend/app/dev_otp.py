"""Run locally on the backend machine; never publish codes or this directory."""
import os
import sys
import uuid
from .auth import otp_directory

if __name__ == '__main__':
    if os.getenv('SENDOH_ENV') != 'development':
        raise SystemExit(
            'Local development only. In PowerShell, run:\n'
            '  $env:SENDOH_ENV="development"\n'
            'Then repeat this command from services/backend.\n'
            'For a Render staging challenge, read SENDOH_STAGING_OTP in Render logs instead.'
        )
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python -m app.dev_otp CHALLENGE_ID')
    challenge_id = str(uuid.UUID(sys.argv[1]))
    path = otp_directory() / challenge_id
    if not path.exists():
        raise SystemExit(
            'Code unavailable in this local backend. Request a new code from the local API.\n'
            'A challenge created by https://sendoh.onrender.com exists in Render, not in local SQLite.'
        )
    print(path.read_text())
