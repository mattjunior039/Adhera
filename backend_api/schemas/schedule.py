from datetime import time
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class ScheduleBase(BaseModel):
    day_of_week: str = Field(..., min_length=1, max_length=20)
    time_of_day: time
    notes: Optional[str] = Field(default=None, max_length=500)


class ScheduleCreate(ScheduleBase):
    user_id: int
    medication_id: int


class ScheduleResponse(ScheduleBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    medication_id: int
