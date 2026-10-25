from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class CompartmentInventoryUpdate(BaseModel):
    medication_id: int
    pill_count: int = Field(ge=0, le=3)


class CompartmentInventoryResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    day_of_week: str
    period: str
    medication_id: int
    medication_name: str
    pill_count: int = Field(ge=0, le=3)
    updated_at: datetime
