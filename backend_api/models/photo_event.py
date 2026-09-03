from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING, Optional

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

try:
    from backend_api.database import Base
except ImportError:  # pragma: no cover - script execution fallback
    from database import Base

if TYPE_CHECKING:
    from .inference_result import InferenceResult


class PhotoEvent(Base):
    __tablename__ = "photo_events"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    medication_id: Mapped[Optional[int]] = mapped_column(ForeignKey("medications.id", ondelete="SET NULL"), nullable=True, index=True)
    event_type: Mapped[str] = mapped_column(String(100), nullable=False)
    photo_path: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    event_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)
    notes: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)

    user: Mapped["User"] = relationship(back_populates="photo_events")
    inference_results: Mapped[list["InferenceResult"]] = relationship(
        back_populates="photo_event",
        foreign_keys="[InferenceResult.photo_event_id]",
        cascade="all, delete-orphan",
    )
    baseline_inference_results: Mapped[list["InferenceResult"]] = relationship(
        back_populates="baseline_event",
        foreign_keys="[InferenceResult.baseline_event_id]",
        cascade="all, delete-orphan",
    )
