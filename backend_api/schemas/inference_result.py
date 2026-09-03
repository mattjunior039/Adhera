from pydantic import BaseModel, ConfigDict, Field


class InferenceResultBase(BaseModel):
    compartment_index: int = Field(..., ge=0, le=13)
    is_changed: bool
    confidence: float = Field(..., ge=0.0, le=1.0)


class InferenceResultCreate(InferenceResultBase):
    photo_event_id: int
    baseline_event_id: int


class InferenceResultResponse(InferenceResultBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    photo_event_id: int
    baseline_event_id: int


class AnalyzePhotoRequest(BaseModel):
    baseline_event_id: int
