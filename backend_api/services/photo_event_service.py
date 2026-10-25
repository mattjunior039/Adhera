from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend_api.models.photo_event import PhotoEvent
from backend_api.schemas.photo_event import PhotoEventCreate


async def create_photo_event(db: AsyncSession, photo_event_in: PhotoEventCreate) -> PhotoEvent:
    photo_event = PhotoEvent(**photo_event_in.model_dump(exclude_none=True))
    db.add(photo_event)
    await db.commit()
    await db.refresh(photo_event)
    return photo_event


async def get_user_photo_events(db: AsyncSession, user_id: int) -> list[PhotoEvent]:
    result = await db.execute(
        select(PhotoEvent).where(PhotoEvent.user_id == user_id).order_by(PhotoEvent.event_time.desc())
    )
    return list(result.scalars().all())
