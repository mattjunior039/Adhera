from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend_api.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class CompartmentInventory(Base):
    __tablename__ = "compartment_inventory"
    __table_args__ = (
        UniqueConstraint("user_id", "day_of_week", "period", name="uq_compartment_user_day_period"),
        CheckConstraint("period IN ('AM', 'PM')", name="ck_compartment_period"),
        CheckConstraint("pill_count BETWEEN 0 AND 3", name="ck_compartment_pill_count"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    day_of_week: Mapped[str] = mapped_column(String(10), nullable=False)
    period: Mapped[str] = mapped_column(String(2), nullable=False)
    medication_id: Mapped[int] = mapped_column(
        ForeignKey("medications.id", ondelete="CASCADE"), nullable=False
    )
    pill_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=_utcnow)

    medication = relationship("Medication")
