"""Shared execution guards, without importing API routers."""
import os
from sqlalchemy import select
from .models import PersonExecution


def enabled(config):
    return config is not None and os.getenv('SENDOH_SANDBOX_PERSON_PAYMENTS') == '1'


def request_execution(db, request_id):
    return db.scalar(select(PersonExecution).where(PersonExecution.request_id == request_id,
        PersonExecution.state != 'FAILED'))


def request_payment_state(db, request_id):
    e = request_execution(db, request_id)
    if e is None:
        return None
    return 'PAID' if e.state == 'SUCCEEDED' else 'PAYMENT_REVIEW' if e.state == 'REVIEW' else 'PROCESSING'
