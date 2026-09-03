from __future__ import annotations

from typing import Optional

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship

try:
    from backend_api.database import Base
except ImportError:  # pragma: no cover - script execution fallback
    from database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    phone: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False, default="")

    medications: Mapped[list["Medication"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    schedules: Mapped[list["Schedule"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    photo_events: Mapped[list["PhotoEvent"]] = relationship(back_populates="user", cascade="all, delete-orphan")
