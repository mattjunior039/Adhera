from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Optional

from sqlalchemy import Date, Float, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

try:
    from backend_api.database import Base
except ImportError:  # pragma: no cover
    from database import Base


class DoseOutcome(Base):
    __tablename__ = "dose_outcomes"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    # nullable so a manual log can exist without a backend schedule row
    schedule_id: Mapped[Optional[int]] = mapped_column(ForeignKey("schedules.id", ondelete="SET NULL"), nullable=True, index=True)
    dose_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    # taken | missed | partial | unknown
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    confidence: Mapped[float] = mapped_column(Float, default=1.0)
    photo_event_id: Mapped[Optional[int]] = mapped_column(ForeignKey("photo_events.id", ondelete="SET NULL"), nullable=True)
    logged_at: Mapped[datetime] = mapped_column(default=lambda: datetime.now(timezone.utc))
    notes: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
