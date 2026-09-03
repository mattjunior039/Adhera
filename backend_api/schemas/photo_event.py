from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class PhotoEventBase(BaseModel):
    event_type: str = Field(..., min_length=1, max_length=100)
    photo_path: Optional[str] = Field(default=None, max_length=500)
    notes: Optional[str] = Field(default=None, max_length=500)


class PhotoEventCreate(PhotoEventBase):
    user_id: int
    medication_id: Optional[int] = None
    event_time: Optional[datetime] = None


class PhotoEventResponse(PhotoEventBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    medication_id: Optional[int] = None
    event_time: datetime
