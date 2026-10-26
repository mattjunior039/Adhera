from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend_api.models.adhera_orientation_profile import AdheraOrientationProfile


async def get_orientation_profile(db: AsyncSession, user_id: int) -> Optional[AdheraOrientationProfile]:
    return (
        await db.execute(select(AdheraOrientationProfile).where(AdheraOrientationProfile.user_id == user_id))
    ).scalar_one_or_none()


async def set_orientation_profile(
    db: AsyncSession, user_id: int, column_order: str
) -> AdheraOrientationProfile:
    if column_order not in ("forward", "reversed"):
        raise ValueError("column_order must be 'forward' or 'reversed'")
    profile = await get_orientation_profile(db, user_id)
    if profile is None:
        profile = AdheraOrientationProfile(user_id=user_id, column_order=column_order)
        db.add(profile)
    else:
        profile.column_order = column_order
    profile.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(profile)
    return profile
