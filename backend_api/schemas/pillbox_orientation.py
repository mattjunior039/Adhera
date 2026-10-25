from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class PillboxOrientationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    column_order: str
    updated_at: datetime


class PillboxOrientationUpdate(BaseModel):
    column_order: str = Field(..., pattern="^(forward|reversed)$")
