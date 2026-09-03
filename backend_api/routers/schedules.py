from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

try:
    from backend_api.database import get_db
    from backend_api.schemas.schedule import ScheduleCreate, ScheduleResponse
    from backend_api.services.schedule_service import create_schedule, get_user_schedule
except ImportError:  # pragma: no cover - script execution fallback
    from database import get_db
    from schemas.schedule import ScheduleCreate, ScheduleResponse
    from services.schedule_service import create_schedule, get_user_schedule

router = APIRouter(prefix="", tags=["schedules"])


@router.post("/schedules", response_model=ScheduleResponse, status_code=status.HTTP_201_CREATED)
async def create_new_schedule(schedule: ScheduleCreate, db: AsyncSession = Depends(get_db)) -> ScheduleResponse:
    try:
        created = await create_schedule(db, schedule)
        return ScheduleResponse.model_validate(created)
    except Exception as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/schedule/{user_id}", response_model=list[ScheduleResponse])
async def get_user_schedules(user_id: int, db: AsyncSession = Depends(get_db)) -> list[ScheduleResponse]:
    schedules = await get_user_schedule(db, user_id)
    return [ScheduleResponse.model_validate(item) for item in schedules]
