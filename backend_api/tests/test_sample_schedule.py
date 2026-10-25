import unittest
from datetime import time

from backend_api.database import Base
from backend_api.models import DoseOutcome, Medication, Schedule, User
from backend_api.scripts.seed_sample_schedule import (
    DAYS,
    EMAIL,
    NAMES,
    PM_COUNTS,
    sample_entries,
    seed_sample_schedule,
)
from backend_api.services.compartment_inventory_service import initialize_test_inventory
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine


class SampleScheduleTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.engine = create_async_engine("sqlite+aiosqlite:///:memory:")
        async with self.engine.begin() as connection:
            await connection.run_sync(Base.metadata.create_all)
        self.sessions = async_sessionmaker(self.engine, expire_on_commit=False)

    async def asyncTearDown(self):
        await self.engine.dispose()

    def test_exact_pm_quantities_and_reproducible_small_am_quantities(self):
        expected = [
            (2, 0, 1, 1),
            (2, 1, 2, 1),
            (1, 1, 1, 1),
            (1, 1, 1, 1),
            (0, 2, 1, 1),
            (2, 1, 1, 1),
            (0, 1, 1, 3),
        ]
        entries = sample_entries()
        self.assertEqual(PM_COUNTS, tuple(expected))
        self.assertEqual(entries, sample_entries())
        for day, counts in zip(DAYS, expected):
            actual = {name: count for d, t, name, count in entries if d == day and t == time(18)}
            self.assertEqual(actual, {name: count for name, count in zip(NAMES, counts) if count})
        am = [(d, t, n, c) for d, t, n, c in entries if t == time(8)]
        self.assertEqual(len(am), 28)
        self.assertTrue(all(1 <= count <= 2 for _, _, _, count in am))

    async def test_persistent_idempotent_seed_replaces_only_unlinked_starter_data(self):
        async with self.sessions() as db:
            sample = User(email=EMAIL, full_name="Adhera Test")
            other = User(email="other@example.com", full_name="Other")
            db.add_all([sample, other])
            await db.flush()
            medication = Medication(user_id=sample.id, name="Ibuprofen")
            other_med = Medication(user_id=other.id, name="Iron")
            db.add_all([medication, other_med])
            await db.flush()
            db.add_all(
                [
                    Schedule(
                        user_id=sample.id,
                        medication_id=medication.id,
                        day_of_week="Sunday",
                        time_of_day=time(20),
                        notes="1 pills loaded",
                    ),
                    Schedule(
                        user_id=sample.id,
                        medication_id=medication.id,
                        day_of_week="Monday",
                        time_of_day=time(12),
                        notes="User-created schedule",
                    ),
                    Schedule(
                        user_id=other.id,
                        medication_id=other_med.id,
                        day_of_week="Friday",
                        time_of_day=time(18),
                        notes="Other user's schedule",
                    ),
                ]
            )
            await db.commit()
            self.assertEqual(await seed_sample_schedule(db), 53)
            await db.commit()
            first = list((await db.execute(select(Schedule))).scalars())
            ids = {s.id for s in first}
            await seed_sample_schedule(db)
            await db.commit()
            second = list((await db.execute(select(Schedule))).scalars())
            self.assertEqual(ids, {s.id for s in second})
            self.assertEqual(len(second), 55)
            self.assertFalse(any(s.notes == "1 pills loaded" for s in second))
            meds = list(
                (await db.execute(select(Medication).where(Medication.user_id == sample.id))).scalars()
            )
            self.assertEqual({m.name for m in meds}, set(NAMES))
            self.assertTrue(all("not a prescription" in m.instructions for m in meds))
            await initialize_test_inventory(db, sample.id)
            after_inventory = list((await db.execute(select(Schedule))).scalars())
            self.assertEqual(len(after_inventory), 55)

    async def test_missing_sample_user_is_not_created(self):
        async with self.sessions() as db:
            with self.assertRaisesRegex(ValueError, "sample account first"):
                await seed_sample_schedule(db)
            self.assertEqual(list((await db.execute(select(Medication))).scalars()), [])

    async def test_explicit_reset_clears_sample_history_and_preserves_other_account(self):
        async with self.sessions() as db:
            user = User(
                email=EMAIL, full_name="Adhera Test", password_hash="keep-this-hash", phone="00000000000000"
            )
            other = User(email="other@example.com", full_name="Other")
            db.add_all([user, other])
            await db.flush()
            own_med = Medication(user_id=user.id, name="Old demo")
            other_med = Medication(user_id=other.id, name="Other medication")
            db.add_all([own_med, other_med])
            await db.flush()
            old = Schedule(
                user_id=user.id,
                medication_id=own_med.id,
                day_of_week="Sunday",
                time_of_day=time(20),
                notes="1 pills loaded",
            )
            db.add(old)
            await db.flush()
            from datetime import date

            db.add(DoseOutcome(user_id=user.id, schedule_id=old.id, dose_date=date.today(), status="taken"))
            await db.commit()
            await seed_sample_schedule(db, reset_sample_data=True)
            await db.commit()
            self.assertEqual(list((await db.execute(select(DoseOutcome))).scalars()), [])
            self.assertEqual(len(list((await db.execute(select(Schedule))).scalars())), 53)
            saved = await db.get(User, user.id)
            self.assertEqual(saved.password_hash, "keep-this-hash")
            self.assertEqual(saved.phone, "00000000000000")
            self.assertIsNotNone(await db.get(Medication, other_med.id))

    async def test_starter_with_history_is_not_deleted(self):
        async with self.sessions() as db:
            user = User(email=EMAIL, full_name="Adhera Test")
            db.add(user)
            await db.flush()
            medication = Medication(user_id=user.id, name="Iron")
            db.add(medication)
            await db.flush()
            schedule = Schedule(
                user_id=user.id,
                medication_id=medication.id,
                day_of_week="Sunday",
                time_of_day=time(8),
                notes="1 pills loaded",
            )
            db.add(schedule)
            await db.flush()
            from datetime import date

            db.add(
                DoseOutcome(
                    user_id=user.id, schedule_id=schedule.id, dose_date=date.today(), status="unknown"
                )
            )
            await db.commit()
            with self.assertRaisesRegex(ValueError, "recorded history"):
                await seed_sample_schedule(db)
            await db.rollback()
            self.assertEqual(len(list((await db.execute(select(Schedule))).scalars())), 1)
