from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class DoseVerificationEventResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True, protected_namespaces=("model_validate", "model_dump"))

    id: int
    user_id: int
    medication_id: Optional[int]
    recognized_medication: Optional[str] = None
    inventory_updated: bool = False
    prototype: Optional[str] = None
    reason: Optional[str] = None
    evidence_scope: Optional[str] = None
    analysis_mode: Optional[str] = None
    destination_label: Optional[str] = None
    removed_count: Optional[int] = Field(default=None, ge=0)
    transferred_count: Optional[int] = Field(default=None, ge=0)
    model_provenance: dict[str, str] = Field(default_factory=dict)
    schedule_id: Optional[int]
    compartment_index: Optional[int] = Field(default=None, ge=0, le=13)
    assumed_label: Optional[str]
    expected_label: Optional[str]
    am_row: Optional[int]
    period_confident: bool
    orientation_calibrated: bool
    wrong_slot: bool
    pre_count: Optional[int]
    post_count: Optional[int]
    event_type: str
    confidence: float = Field(..., ge=0.0, le=1.0)
    requires_review: bool
    frames_sampled: int
    frames_accepted: int
    created_at: datetime
