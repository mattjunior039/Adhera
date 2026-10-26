from __future__ import annotations

from datetime import datetime, timezone
from typing import TYPE_CHECKING, Optional

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend_api.database import Base

if TYPE_CHECKING:
    from .user import User


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class DoseVerificationEvent(Base):
    """Result of analyzing a before/after (open -> remove -> close) verification video."""

    __tablename__ = "dose_verification_events"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    medication_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("medications.id", ondelete="SET NULL"), nullable=True, index=True
    )
    schedule_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("schedules.id", ondelete="SET NULL"), nullable=True, index=True
    )
    video_path: Mapped[str] = mapped_column(String(500), nullable=False)

    # Auto-detected compartment (0-13) that changed the most during the clip.
    compartment_index: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    # Best-effort SUN..SAT / AM-PM guess; "forward" order until orientation is calibrated.
    assumed_label: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    # Derived from the linked schedule (if any): what slot the user said they'd verify.
    expected_label: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    # Which canonical row (0/1) was classified as AM by lid color for this clip.
    am_row: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    # False when the AM/PM color read was ambiguous (e.g. an off-angle reference frame) —
    # auto-calibration and wrong-slot detection are skipped in that case.
    period_confident: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    # True once a per-user column-order profile exists (see AdheraOrientationProfile).
    orientation_calibrated: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    # assumed_label != expected_label while calibrated — the user may have opened the wrong slot.
    wrong_slot: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    pre_count: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    post_count: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    # "REMOVED_AS_EXPECTED" | "PARTIAL_REMOVAL" | "NO_REMOVAL_DETECTED" | "EXTRA_PILL_PRESENT" | "INCONCLUSIVE"
    event_type: Mapped[str] = mapped_column(String(40), nullable=False)
    confidence: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    requires_review: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    frames_sampled: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    frames_accepted: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=_utcnow)

    user: Mapped["User"] = relationship()
