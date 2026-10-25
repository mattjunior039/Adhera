from __future__ import annotations

from datetime import datetime, time, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from backend_api.models.compartment_inventory import CompartmentInventory
from backend_api.models.medication import Medication
from backend_api.models.schedule import Schedule
from backend_api.models.user import User

WEEKDAYS = ("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
PERIODS = ("AM", "PM")

# Deterministic starter contents for the explicit extraction-test setup endpoint.
TEST_SLOT_SEED = (
    ("acetaminophen", 2),
    ("ibuprofen", 1),
    ("ibuprofen", 0),
    ("acetaminophen", 2),
    ("acetaminophen", 1),
    ("ibuprofen", 3),
    ("ibuprofen", 2),
    ("acetaminophen", 1),
    ("acetaminophen", 0),
    ("ibuprofen", 2),
    ("ibuprofen", 1),
    ("acetaminophen", 3),
    ("acetaminophen", 2),
    ("ibuprofen", 1),
)

TEST_MEDICATIONS = {
    "acetaminophen": ("Acetaminophen", "500 mg"),
    "ibuprofen": ("Ibuprofen", "200 mg"),
}


async def initialize_test_inventory(db: AsyncSession, user_id: int) -> list[CompartmentInventory]:
    user = await db.get(User, user_id)
    if user is None:
        raise ValueError("User was not found")

    medications = list(
        (await db.execute(select(Medication).where(Medication.user_id == user_id))).scalars().all()
    )
    by_name = {med.name.casefold(): med for med in medications}
    for key, (name, dosage) in TEST_MEDICATIONS.items():
        if name.casefold() not in by_name:
            medication = Medication(user_id=user_id, name=name, dosage=dosage)
            db.add(medication)
            await db.flush()
            by_name[name.casefold()] = medication

    existing = list(
        (await db.execute(select(CompartmentInventory).where(CompartmentInventory.user_id == user_id)))
        .scalars()
        .all()
    )
    existing_keys = {(slot.day_of_week, slot.period) for slot in existing}
    for index, (day, period) in enumerate((day, period) for day in WEEKDAYS for period in PERIODS):
        if (day, period) in existing_keys:
            continue
        medication_key, pill_count = TEST_SLOT_SEED[index]
        medication = by_name[TEST_MEDICATIONS[medication_key][0].casefold()]
        db.add(
            CompartmentInventory(
                user_id=user_id,
                day_of_week=day,
                period=period,
                medication_id=medication.id,
                pill_count=pill_count,
            )
        )

    await db.flush()
    slots = await get_inventory(db, user_id)
    schedules = list((await db.execute(select(Schedule).where(Schedule.user_id == user_id))).scalars().all())
    scheduled_periods = {
        (schedule.day_of_week, "AM" if schedule.time_of_day.hour < 12 else "PM") for schedule in schedules
    }
    has_demo_schedule = any((schedule.notes or "").startswith("DEMO ONLY:") for schedule in schedules)
    for slot in slots:
        if has_demo_schedule:
            break
        key = (slot.day_of_week, slot.period)
        if key in scheduled_periods:
            continue
        db.add(
            Schedule(
                user_id=user_id,
                medication_id=slot.medication_id,
                day_of_week=slot.day_of_week,
                time_of_day=time(8, 0) if slot.period == "AM" else time(20, 0),
                notes=f"{slot.pill_count} pills loaded",
            )
        )
        scheduled_periods.add(key)

    await db.commit()
    return await get_inventory(db, user_id)


async def get_inventory(db: AsyncSession, user_id: int) -> list[CompartmentInventory]:
    result = await db.execute(
        select(CompartmentInventory)
        .options(selectinload(CompartmentInventory.medication))
        .where(CompartmentInventory.user_id == user_id)
    )
    slots = list(result.scalars().all())
    day_order = {day: index for index, day in enumerate(WEEKDAYS)}
    period_order = {period: index for index, period in enumerate(PERIODS)}
    return sorted(
        slots, key=lambda slot: (day_order.get(slot.day_of_week, 99), period_order.get(slot.period, 99))
    )


async def update_inventory_slot(
    db: AsyncSession,
    user_id: int,
    slot_id: int,
    medication_id: int,
    pill_count: int,
) -> CompartmentInventory | None:
    if not 0 <= pill_count <= 3:
        raise ValueError("pill_count must be between 0 and 3")
    slot = await db.get(CompartmentInventory, slot_id)
    medication = await db.get(Medication, medication_id)
    if slot is None or slot.user_id != user_id:
        return None
    if medication is None or medication.user_id != user_id:
        raise ValueError("Medication does not belong to this user")
    if medication.name.casefold() not in {"acetaminophen", "ibuprofen"}:
        raise ValueError("Only acetaminophen and ibuprofen are supported in extraction-test mode")

    slot.medication_id = medication_id
    slot.pill_count = pill_count
    slot.updated_at = datetime.now(timezone.utc)
    inventory = await get_inventory(db, user_id)
    return next(item for item in inventory if item.id == slot_id)


async def apply_video_count(
    db: AsyncSession,
    *,
    user_id: int,
    slot_id: int,
    medication_id: int,
    post_count: int,
) -> bool:
    slot = await db.get(CompartmentInventory, slot_id)
    if slot is None or slot.user_id != user_id or slot.medication_id != medication_id:
        return False
    if not 0 <= post_count <= 3:
        return False
    slot.pill_count = post_count
    slot.updated_at = datetime.now(timezone.utc)
    return True
