"""Explicit sandbox tariff arithmetic. No default or inferred provider rates."""
import hashlib
import json
import os
from pydantic import BaseModel, ConfigDict, Field, model_validator

LIMIT = 1_000_000_000


class FeePolicy(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True, frozen=True)
    version: str = Field(min_length=1, max_length=60, pattern=r'^[A-Za-z0-9_.-]+$')
    collect_bps: int = Field(ge=0, lt=10000)
    collect_fixed: int = Field(ge=0, le=LIMIT)
    payout_bps: int = Field(ge=0, lt=10000)
    payout_fixed: int = Field(ge=0, le=LIMIT)
    sendoh_bps: int = Field(ge=0, lt=10000)
    sendoh_min: int = Field(ge=0, le=LIMIT)
    sendoh_cap: int = Field(ge=0, le=LIMIT)

    @model_validator(mode='after')
    def bounds(self):
        if self.sendoh_cap < self.sendoh_min:
            raise ValueError('Fee cap must not be below the minimum.')
        return self

    @property
    def fingerprint(self):
        return hashlib.sha256(json.dumps(self.model_dump(), sort_keys=True).encode()).hexdigest()


def configured_policy():
    raw = os.getenv('SENDOH_SANDBOX_PERSON_FEE_POLICY')
    if not raw:
        return None
    # Invalid configuration disables quotes rather than assuming free payments.
    try:
        return FeePolicy.model_validate_json(raw)
    except ValueError:
        return None


def ceiling_div(n, d):
    return (n + d - 1) // d


def calculate(principal: int, policy: FeePolicy):
    if type(principal) is not int or not 0 < principal <= LIMIT:
        raise ValueError('Principal must be a positive whole XAF amount.')
    service = min(policy.sendoh_cap, max(policy.sendoh_min,
        ceiling_div(principal * policy.sendoh_bps, 10000)))
    payout = policy.payout_fixed + ceiling_div(principal * policy.payout_bps, 10000)
    required_net = principal + payout + service
    # Smallest whole debit that covers a fee rounded UP on the gross debit.
    total = ceiling_div((required_net + policy.collect_fixed) * 10000,
                        10000 - policy.collect_bps)
    if total > LIMIT:
        raise ValueError('Total exceeds the payment limit.')
    collect = policy.collect_fixed + ceiling_div(total * policy.collect_bps, 10000)
    assert total - collect == required_net
    return dict(recipient_amount=principal, sendoh_fee=service,
        collection_fee=collect, delivery_fee=payout,
        total_fees=total - principal, total_debit=total,
        expected_collection_net=required_net, currency='XAF')
