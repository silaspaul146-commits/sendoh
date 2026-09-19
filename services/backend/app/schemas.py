from typing import Annotated, Literal
from pydantic import BaseModel, ConfigDict, Field, AwareDatetime, model_validator

Money = Annotated[int, Field(strict=True, gt=0, le=1_000_000_000_000)]
class ParticipantInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    name: str = Field(min_length=1, max_length=120)
    expected_amount: Money | None = None

class CollectionInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    name: str = Field(min_length=1, max_length=120)
    description: str = Field(default='', max_length=2000)
    currency: Literal['XAF'] = 'XAF'
    target_amount: Money | None = None
    deadline_at: AwareDatetime | None = None
    mode: Literal['ANY_AMOUNT', 'EXPECTED_TOTAL', 'MINIMUM_TOTAL'] = 'ANY_AMOUNT'
    expected_amount: Money | None = None
    participants: list[ParticipantInput] = Field(default_factory=list, max_length=200)
    publish: bool = True

    @model_validator(mode='after')
    def contribution_policy(self):
        if self.mode == 'ANY_AMOUNT':
            if self.expected_amount is not None or any(p.expected_amount is not None for p in self.participants):
                raise ValueError('Any-amount collections cannot impose participant expectations')
        elif self.expected_amount is None:
            raise ValueError('An expected or minimum total is required')
        return self
