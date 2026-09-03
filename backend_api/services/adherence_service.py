from __future__ import annotations

from datetime import date
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

try:
    from backend_api.models.dose_outcome import DoseOutcome
    from backend_api.models.inference_result import InferenceResult
    from backend_api.models.photo_event import PhotoEvent
    from backend_api.models.schedule import Schedule
except ImportError:  # pragma: no cover
    from models.dose_outcome import DoseOutcome
    from models.inference_result import InferenceResult
    from models.photo_event import PhotoEvent
    from models.schedule import Schedule

_WEEKDAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']


async def log_dose(
    db: AsyncSession,
    user_id: int,
    schedule_id: int,
    status: str,
    confidence: float = 1.0,
    photo_event_id: Optional[int] = None,
    notes: Optional[str] = None,
) -> DoseOutcome:
    """Create or overwrite today's outcome for this schedule slot."""
    today = date.today()
    existing = (await db.execute(
        select(DoseOutcome).where(
            DoseOutcome.user_id == user_id,
            DoseOutcome.schedule_id == schedule_id,
            DoseOutcome.dose_date == today,
        )
    )).scalar_one_or_none()

    if existing is not None:
        existing.status = status
        existing.confidence = confidence
        existing.photo_event_id = photo_event_id
        existing.notes = notes
        outcome = existing
    else:
        outcome = DoseOutcome(
            user_id=user_id,
            schedule_id=schedule_id,
            dose_date=today,
            status=status,
            confidence=confidence,
            photo_event_id=photo_event_id,
            notes=notes,
        )
        db.add(outcome)

    await db.commit()
    await db.refresh(outcome)
    return outcome


async def get_today_outcomes(db: AsyncSession, user_id: int) -> list[DoseOutcome]:
    today = date.today()
    result = await db.execute(
        select(DoseOutcome)
        .where(DoseOutcome.user_id == user_id, DoseOutcome.dose_date == today)
        .order_by(DoseOutcome.id)
    )
    return list(result.scalars().all())


async def evaluate_from_photos(db: AsyncSession, user_id: int) -> list[DoseOutcome]:
    """Infer today's adherence by correlating photo-event inference results with the
    scheduled dose times.  Slots without a matching photo within ±3 hours stay 'unknown'."""
    today = date.today()
    today_name = _WEEKDAYS[today.weekday()]

    schedules = list(
        (await db.execute(
            select(Schedule).where(Schedule.user_id == user_id, Schedule.day_of_week == today_name)
        )).scalars().all()
    )

    today_events = [
        e for e in (
            await db.execute(
                select(PhotoEvent)
                .where(PhotoEvent.user_id == user_id)
                .order_by(PhotoEvent.event_time.desc())
            )
        ).scalars().all()
        if e.event_time.date() == today
    ]

    outcomes: list[DoseOutcome] = []
    for schedule in schedules:
        scheduled_hour = schedule.time_of_day.hour if schedule.time_of_day else 9

        # Pick the closest photo event within a ±3-hour window
        best_event: Optional[PhotoEvent] = None
        best_diff = float('inf')
        for event in today_events:
            diff = abs(event.event_time.hour - scheduled_hour)
            if diff < best_diff and diff <= 3:
                best_diff = diff
                best_event = event

        if best_event is None:
            outcome = await log_dose(db, user_id, schedule.id, 'unknown', confidence=0.0)
        else:
            inferences = list(
                (await db.execute(
                    select(InferenceResult).where(InferenceResult.photo_event_id == best_event.id)
                )).scalars().all()
            )
            if not inferences:
                outcome = await log_dose(db, user_id, schedule.id, 'unknown', 0.5, best_event.id)
            else:
                changed = sum(1 for r in inferences if r.is_changed)
                avg_conf = sum(r.confidence for r in inferences) / len(inferences)
                # ≥2 changed compartments = pills removed = taken
                status = 'taken' if changed >= 2 else ('missed' if changed == 0 else 'partial')
                outcome = await log_dose(db, user_id, schedule.id, status, avg_conf, best_event.id)

        outcomes.append(outcome)

    return outcomes
