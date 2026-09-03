from __future__ import annotations

from typing import TYPE_CHECKING

from sqlalchemy import Boolean, Float, ForeignKey, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship

try:
    from backend_api.database import Base
except ImportError:  # pragma: no cover - script execution fallback
    from database import Base

if TYPE_CHECKING:
    from .photo_event import PhotoEvent


class InferenceResult(Base):
    __tablename__ = "inference_results"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    photo_event_id: Mapped[int] = mapped_column(ForeignKey("photo_events.id", ondelete="CASCADE"), nullable=False, index=True)
    baseline_event_id: Mapped[int] = mapped_column(ForeignKey("photo_events.id", ondelete="CASCADE"), nullable=False, index=True)
    compartment_index: Mapped[int] = mapped_column(Integer, nullable=False)
    is_changed: Mapped[bool] = mapped_column(Boolean, nullable=False)
    confidence: Mapped[float] = mapped_column(Float, nullable=False)

    photo_event: Mapped["PhotoEvent"] = relationship(
        foreign_keys=[photo_event_id],
        back_populates="inference_results",
    )
    baseline_event: Mapped["PhotoEvent"] = relationship(
        foreign_keys=[baseline_event_id],
        back_populates="baseline_inference_results",
    )
