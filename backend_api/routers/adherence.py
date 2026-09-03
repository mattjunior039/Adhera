from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

try:
    from backend_api.database import get_db
    from backend_api.schemas.dose_outcome import DoseOutcomeResponse, LogDoseRequest
    from backend_api.services.adherence_service import evaluate_from_photos, get_today_outcomes, log_dose
except ImportError:  # pragma: no cover
    from database import get_db
    from schemas.dose_outcome import DoseOutcomeResponse, LogDoseRequest
    from services.adherence_service import evaluate_from_photos, get_today_outcomes, log_dose

router = APIRouter(prefix="/adherence", tags=["adherence"])


@router.post("/log", response_model=DoseOutcomeResponse, status_code=status.HTTP_200_OK)
async def log_dose_endpoint(
    request: LogDoseRequest, db: AsyncSession = Depends(get_db)
) -> DoseOutcomeResponse:
    """Manually mark a scheduled dose as taken/missed/unknown."""
    outcome = await log_dose(
        db,
        user_id=request.user_id,
        schedule_id=request.schedule_id,
        status=request.status,
        confidence=request.confidence,
        notes=request.notes,
    )
    return DoseOutcomeResponse.model_validate(outcome)


@router.get("/today/{user_id}", response_model=list[DoseOutcomeResponse])
async def get_today(user_id: int, db: AsyncSession = Depends(get_db)) -> list[DoseOutcomeResponse]:
    """Return all logged dose outcomes for today."""
    outcomes = await get_today_outcomes(db, user_id)
    return [DoseOutcomeResponse.model_validate(o) for o in outcomes]


@router.post("/evaluate/{user_id}", response_model=list[DoseOutcomeResponse])
async def evaluate_adherence(
    user_id: int, db: AsyncSession = Depends(get_db)
) -> list[DoseOutcomeResponse]:
    """Auto-evaluate today's adherence from uploaded photo-event inference results."""
    outcomes = await evaluate_from_photos(db, user_id)
    return [DoseOutcomeResponse.model_validate(o) for o in outcomes]
