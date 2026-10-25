from __future__ import annotations

from datetime import date, datetime, time
from typing import Optional

from sqlalchemy import select
from sqlalchemy.exc import MultipleResultsFound
from sqlalchemy.ext.asyncio import AsyncSession

from backend_api.models.dose_outcome import DoseOutcome
from backend_api.models.inference_result import InferenceResult
from backend_api.models.photo_event import PhotoEvent
from backend_api.models.schedule import Schedule

_WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
_MATCH_WINDOW_MINUTES = 3 * 60


def _minutes_since_midnight(value: datetime | time) -> float:
    return value.hour * 60 + value.minute + value.second / 60 + value.microsecond / 60_000_000


def _find_closest_photo_event(
    events: list[PhotoEvent],
    scheduled_time: time,
    used_event_ids: set[int],
) -> Optional[PhotoEvent]:
    best_event: Optional[PhotoEvent] = None
    best_diff = float("inf")
    scheduled_minutes = _minutes_since_midnight(scheduled_time)

    for event in events:
        if event.id in used_event_ids:
            continue
        diff = abs(_minutes_since_midnight(event.event_time) - scheduled_minutes)
        if diff < best_diff and diff <= _MATCH_WINDOW_MINUTES:
            best_diff = diff
            best_event = event

    return best_event


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
    existing = (
        await db.execute(
            select(DoseOutcome).where(
                DoseOutcome.user_id == user_id,
                DoseOutcome.schedule_id == schedule_id,
                DoseOutcome.dose_date == today,
            )
        )
    ).scalar_one_or_none()

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
        (
            await db.execute(
                select(Schedule).where(Schedule.user_id == user_id, Schedule.day_of_week == today_name)
            )
        )
        .scalars()
        .all()
    )

    today_events = [
        e
        for e in (
            await db.execute(
                select(PhotoEvent).where(PhotoEvent.user_id == user_id).order_by(PhotoEvent.event_time.desc())
            )
        )
        .scalars()
        .all()
        if e.event_time.date() == today
    ]

    schedule_events: list[tuple[Schedule, Optional[PhotoEvent]]] = []
    used_event_ids: set[int] = set()
    for schedule in schedules:
        scheduled_time = schedule.time_of_day or time(9, 0)
        best_event = _find_closest_photo_event(today_events, scheduled_time, used_event_ids)
        if best_event is not None:
            used_event_ids.add(best_event.id)
        schedule_events.append((schedule, best_event))

    matched_event_ids = {event.id for _, event in schedule_events if event is not None}
    inferences_by_event: dict[int, list[InferenceResult]] = {}
    if matched_event_ids:
        inference_rows = await db.execute(
            select(InferenceResult).where(InferenceResult.photo_event_id.in_(matched_event_ids))
        )
        for inference in inference_rows.scalars().all():
            inferences_by_event.setdefault(inference.photo_event_id, []).append(inference)

    outcome_specs: list[tuple[Schedule, str, float, Optional[int], Optional[str]]] = []
    for schedule, best_event in schedule_events:
        if best_event is None:
            outcome_specs.append((schedule, "unknown", 0.0, None, None))
        else:
            inferences = inferences_by_event.get(best_event.id, [])
            if not inferences:
                outcome_specs.append((schedule, "unknown", 0.5, best_event.id, None))
            else:
                # Never let glare/blur/occlusion masquerade as "unchanged" (missed dose).
                readable = [r for r in inferences if r.state not in ("occluded", "low_quality")]
                if len(readable) < len(inferences) / 2:
                    outcome_specs.append(
                        (
                            schedule,
                            "unknown",
                            0.3,
                            best_event.id,
                            "Too many compartments were occluded or low quality to verify.",
                        )
                    )
                else:
                    changed = sum(1 for r in readable if r.is_changed)
                    avg_conf = sum(r.confidence for r in readable) / len(readable)
                    # >=2 changed compartments means pills were removed.
                    status = "taken" if changed >= 2 else ("missed" if changed == 0 else "partial")
                    outcome_specs.append((schedule, status, avg_conf, best_event.id, None))

    if not outcome_specs:
        return []

    schedule_ids = {schedule.id for schedule, *_ in outcome_specs}
    existing_rows = await db.execute(
        select(DoseOutcome).where(
            DoseOutcome.user_id == user_id,
            DoseOutcome.schedule_id.in_(schedule_ids),
            DoseOutcome.dose_date == today,
        )
    )
    existing_by_schedule: dict[int, DoseOutcome] = {}
    for existing in existing_rows.scalars().all():
        if existing.schedule_id in existing_by_schedule:
            raise MultipleResultsFound()
        existing_by_schedule[existing.schedule_id] = existing

    outcomes: list[DoseOutcome] = []
    for schedule, status, confidence, photo_event_id, notes in outcome_specs:
        outcome = existing_by_schedule.get(schedule.id)
        if outcome is None:
            outcome = DoseOutcome(
                user_id=user_id,
                schedule_id=schedule.id,
                dose_date=today,
            )
            db.add(outcome)
        outcomes.append(outcome)

        outcome.status = status
        outcome.confidence = confidence
        outcome.photo_event_id = photo_event_id
        outcome.notes = notes

    await db.commit()
    return outcomes
