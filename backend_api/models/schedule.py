from __future__ import annotations

from datetime import time
from typing import TYPE_CHECKING, Optional

from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend_api.database import Base

if TYPE_CHECKING:
    from .medication import Medication
    from .user import User


class Schedule(Base):
    __tablename__ = "schedules"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    medication_id: Mapped[int] = mapped_column(
        ForeignKey("medications.id", ondelete="CASCADE"), nullable=False, index=True
    )
    day_of_week: Mapped[str] = mapped_column(String(20), nullable=False)
    time_of_day: Mapped[time] = mapped_column(nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)

    user: Mapped["User"] = relationship(back_populates="schedules")
    medication: Mapped["Medication"] = relationship(back_populates="schedules")
