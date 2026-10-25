from __future__ import annotations

from typing import TYPE_CHECKING, Optional

from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend_api.database import Base

if TYPE_CHECKING:
    from .schedule import Schedule
    from .user import User


class Medication(Base):
    __tablename__ = "medications"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    dosage: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    instructions: Mapped[Optional[str]] = mapped_column(String(1000), nullable=True)

    user: Mapped["User"] = relationship(back_populates="medications")
    schedules: Mapped[list["Schedule"]] = relationship(
        back_populates="medication", cascade="all, delete-orphan"
    )
