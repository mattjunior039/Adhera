from __future__ import annotations

from datetime import datetime, timezone
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend_api.database import Base

if TYPE_CHECKING:
    from .user import User


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class PillboxOrientationProfile(Base):
    """Per-user calibration for which physical direction the pillbox columns run.

    Geometry alone can tell us column order is *consistent within one clip*, but not
    which end is Sunday — that needs either OCR or a one-time/auto-inferred anchor.
    """

    __tablename__ = "pillbox_orientation_profiles"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True
    )
    # "forward" (canonical column 0 = SUN) | "reversed" (canonical column 0 = SAT)
    column_order: Mapped[str] = mapped_column(String(10), nullable=False, default="forward")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow, onupdate=_utcnow
    )

    user: Mapped["User"] = relationship()
