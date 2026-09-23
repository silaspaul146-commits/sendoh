"""Run locally on the backend machine; never publish codes or this directory."""
import os
import sys
import uuid
from .auth import otp_directory

if __name__ == '__main__':
    if os.getenv('SENDOH_ENV') != 'development':
        raise SystemExit('Set SENDOH_ENV=development locally first.')
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python -m app.dev_otp CHALLENGE_ID')
    challenge_id = str(uuid.UUID(sys.argv[1]))
    path = otp_directory() / challenge_id
    if not path.exists():
        raise SystemExit('Code unavailable. Request a new code in the app.')
    print(path.read_text())
