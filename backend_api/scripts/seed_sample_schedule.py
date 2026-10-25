"""Explicitly seed demo schedules for the existing Adhera sample account."""

import argparse
import asyncio
import random
import re
from datetime import time

from backend_api.models import (
    CompartmentInventory,
    DoseOutcome,
    DoseVerificationEvent,
    InferenceResult,
    Medication,
    PhotoEvent,
    PillboxOrientationProfile,
    Schedule,
    User,
)
from sqlalchemy import delete, or_, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

EMAIL = "adherasample@gmail.com"
DEMO_PREFIX = "DEMO ONLY:"
DAYS = ("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
NAMES = ("Ibuprofen", "Acetaminophen", "Iron", "Potassium")
# Counts are in NAMES order, Sunday through Saturday.
PM_COUNTS = (
    (2, 0, 1, 1),
    (2, 1, 2, 1),
    (1, 1, 1, 1),
    (1, 1, 1, 1),
    (0, 2, 1, 1),
    (2, 1, 1, 1),
    (0, 1, 1, 3),
)


def sample_entries() -> list[tuple[str, time, str, int]]:
    rng = random.Random(20261016)
    am_counts = [tuple(rng.randint(1, 2) for _ in NAMES) for _ in DAYS]
    return [
        (day, intake_time, name, count)
        for counts, intake_time in ((am_counts, time(8)), (PM_COUNTS, time(18)))
        for day, daily in zip(DAYS, counts)
        for name, count in zip(NAMES, daily)
        if count
    ]


async def seed_sample_schedule(db: AsyncSession, *, reset_sample_data: bool = False) -> int:
    user = (await db.execute(select(User).where(User.email == EMAIL))).scalar_one_or_none()
    if user is None or user.full_name != "Adhera Test":
        raise ValueError("Create the Adhera Test sample account first; no other account will be modified")
    if reset_sample_data:
        photos = select(PhotoEvent.id).where(PhotoEvent.user_id == user.id)
        await db.execute(
            delete(InferenceResult).where(
                or_(
                    InferenceResult.photo_event_id.in_(photos),
                    InferenceResult.baseline_event_id.in_(photos),
                )
            )
        )
        for model in (
            DoseOutcome,
            DoseVerificationEvent,
            CompartmentInventory,
            PillboxOrientationProfile,
            PhotoEvent,
            Schedule,
            Medication,
        ):
            await db.execute(delete(model).where(model.user_id == user.id))
    medications = {
        med.name.casefold(): med
        for med in (await db.execute(select(Medication).where(Medication.user_id == user.id))).scalars()
    }
    for name in NAMES:
        medication = medications.get(name.casefold())
        if medication is None:
            medication = Medication(user_id=user.id, name=name)
            db.add(medication)
            medications[name.casefold()] = medication
        medication.dosage = "Demo - strength unspecified"
        medication.instructions = (
            f"Demo only: {name}. The scheduled quantities are sample data, not a prescription. "
            "For actual use, follow the product label and your clinician or pharmacist's directions. "
            "Confirm strength, formulation, timing, food requirements and interactions before taking it."
        )
    await db.flush()
    schedules = list((await db.execute(select(Schedule).where(Schedule.user_id == user.id))).scalars())
    legacy = [s for s in schedules if re.fullmatch(r"[0-3] pills loaded", s.notes or "")]
    if legacy:
        ids = [s.id for s in legacy]
        for model in (DoseOutcome, DoseVerificationEvent):
            linked = (await db.execute(select(model.id).where(model.schedule_id.in_(ids)).limit(1))).first()
            if linked:
                raise ValueError(
                    "Starter schedules have recorded history; review them before replacing demo data"
                )
        for schedule in legacy:
            await db.delete(schedule)
    existing = {
        (s.day_of_week, s.time_of_day, s.medication_id): s
        for s in schedules
        if (s.notes or "").startswith(DEMO_PREFIX)
    }
    for day, intake_time, name, count in sample_entries():
        medication = medications[name.casefold()]
        key = (day, intake_time, medication.id)
        schedule = existing.get(key)
        if schedule is None:
            schedule = Schedule(
                user_id=user.id,
                medication_id=medication.id,
                day_of_week=day,
                time_of_day=intake_time,
            )
            db.add(schedule)
        schedule.notes = f"{DEMO_PREFIX} {count} pill(s); not dosing advice."
    await db.flush()
    return len(sample_entries())


async def main(database_url: str, reset_sample_data: bool) -> None:
    engine = create_async_engine(database_url)
    try:
        async with async_sessionmaker(engine)() as db, db.begin():
            count = await seed_sample_schedule(db, reset_sample_data=reset_sample_data)
        print(f"Saved {count} demo schedule entries for Adhera Test (AM 08:00, PM 18:00).")
    finally:
        await engine.dispose()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database-url", required=True, help="Explicit database target; never inferred")
    parser.add_argument(
        "--reset-sample-data",
        action="store_true",
        help="Delete only this sample account's old account data; keep its profile",
    )
    args = parser.parse_args()
    asyncio.run(main(args.database_url, args.reset_sample_data))
