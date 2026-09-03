from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


class LogDoseRequest(BaseModel):
    user_id: int
    schedule_id: int
    status: str  # taken | missed | partial | unknown
    confidence: float = 1.0
    notes: Optional[str] = None


class DoseOutcomeResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    schedule_id: Optional[int]
    dose_date: date
    status: str
    confidence: float
    photo_event_id: Optional[int]
    logged_at: datetime
    notes: Optional[str]
