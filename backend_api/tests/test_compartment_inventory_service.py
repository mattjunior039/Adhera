import asyncio
import unittest

from backend_api.database import Base
from backend_api.models.compartment_inventory import CompartmentInventory
from backend_api.models.medication import Medication
from backend_api.models.schedule import Schedule
from backend_api.models.user import User
from backend_api.services.compartment_inventory_service import (
    PERIODS,
    TEST_SLOT_SEED,
    WEEKDAYS,
    apply_video_count,
    get_inventory,
    initialize_test_inventory,
    update_inventory_slot,
)
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine


class CompartmentInventorySeedTests(unittest.TestCase):
    def test_seed_covers_every_weekday_period_once(self) -> None:
        slots = [(day, period) for day in WEEKDAYS for period in PERIODS]

        self.assertEqual(len(slots), 14)
        self.assertEqual(len(TEST_SLOT_SEED), 14)
        self.assertEqual(set(WEEKDAYS), {day for day, _ in slots})
        self.assertEqual(set(PERIODS), {period for _, period in slots})

    def test_seed_uses_only_supported_medicines_and_counts(self) -> None:
        self.assertEqual({name for name, _ in TEST_SLOT_SEED}, {"acetaminophen", "ibuprofen"})
        self.assertTrue(all(0 <= count <= 3 for _, count in TEST_SLOT_SEED))

    def test_initialization_persists_fourteen_slots_and_is_idempotent(self) -> None:
        async def run() -> None:
            engine = create_async_engine("sqlite+aiosqlite:///:memory:")
            tables = [
                User.__table__,
                Medication.__table__,
                Schedule.__table__,
                CompartmentInventory.__table__,
            ]
            async with engine.begin() as connection:
                await connection.run_sync(lambda sync: Base.metadata.create_all(sync, tables=tables))
            sessions = async_sessionmaker(engine, expire_on_commit=False)
            async with sessions() as db:
                user = User(email="test@example.com", full_name="Test User")
                db.add(user)
                await db.commit()
                await db.refresh(user)

                first = await initialize_test_inventory(db, user.id)
                initial_counts = [slot.pill_count for slot in first]
                second = await initialize_test_inventory(db, user.id)
                self.assertEqual(len(first), 14)
                self.assertEqual(len(second), 14)
                self.assertEqual([slot.pill_count for slot in second], initial_counts)
                self.assertEqual({slot.medication.name for slot in second}, {"Acetaminophen", "Ibuprofen"})
                schedules = (
                    (await db.execute(select(Schedule).where(Schedule.user_id == user.id))).scalars().all()
                )
                self.assertEqual(len(schedules), 14)

                updated = await update_inventory_slot(
                    db,
                    user.id,
                    second[0].id,
                    second[0].medication_id,
                    0,
                )
                self.assertEqual(updated.pill_count, 0)
                self.assertTrue(
                    await apply_video_count(
                        db,
                        user_id=user.id,
                        slot_id=second[0].id,
                        medication_id=second[0].medication_id,
                        post_count=2,
                    )
                )
                self.assertFalse(
                    await apply_video_count(
                        db,
                        user_id=user.id,
                        slot_id=second[0].id,
                        medication_id=second[1].medication_id,
                        post_count=1,
                    )
                )
                await db.commit()
                self.assertEqual((await get_inventory(db, user.id))[0].pill_count, 2)
                self.assertEqual(len(await get_inventory(db, user.id)), 14)
            await engine.dispose()

        asyncio.run(run())


if __name__ == "__main__":
    unittest.main()
