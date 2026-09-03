from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

try:
    from backend_api.models.schedule import Schedule
    from backend_api.schemas.schedule import ScheduleCreate
except ImportError:  # pragma: no cover - script execution fallback
    from models.schedule import Schedule
    from schemas.schedule import ScheduleCreate


async def create_schedule(db: AsyncSession, schedule_in: ScheduleCreate) -> Schedule:
    schedule = Schedule(**schedule_in.model_dump())
    db.add(schedule)
    await db.commit()
    await db.refresh(schedule)
    return schedule


async def get_user_schedule(db: AsyncSession, user_id: int) -> list[Schedule]:
    result = await db.execute(select(Schedule).where(Schedule.user_id == user_id).order_by(Schedule.time_of_day))
    return list(result.scalars().all())
