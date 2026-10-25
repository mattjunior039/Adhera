from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class MedicationBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    dosage: Optional[str] = Field(default=None, max_length=100)
    instructions: Optional[str] = Field(default=None, max_length=1000)


class MedicationCreate(MedicationBase):
    user_id: int


class MedicationUpdate(BaseModel):
    """All fields optional so clients can send only the changed ones."""

    name: Optional[str] = Field(default=None, min_length=1, max_length=255)
    dosage: Optional[str] = Field(default=None, max_length=100)
    instructions: Optional[str] = Field(default=None, max_length=1000)


class MedicationResponse(MedicationBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
