import unittest
from datetime import date, datetime, time, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

from backend_api.models.photo_event import PhotoEvent
from backend_api.services.adherence_service import (
    _find_closest_photo_event,
    evaluate_from_photos,
)


def _query_result(rows):
    return SimpleNamespace(scalars=lambda: SimpleNamespace(all=lambda: rows))


class AdherenceMatchingTests(unittest.TestCase):
    def test_matching_uses_minutes_not_only_hours(self) -> None:
        earlier_event = PhotoEvent(
            id=1,
            event_time=datetime(2026, 9, 15, 9, 59, tzinfo=timezone.utc),
        )
        later_event = PhotoEvent(
            id=2,
            event_time=datetime(2026, 9, 15, 10, 1, tzinfo=timezone.utc),
        )

        result = _find_closest_photo_event([earlier_event, later_event], time(10, 0), set())

        self.assertIs(result, earlier_event)

    def test_photo_event_is_not_reused_for_another_schedule(self) -> None:
        event = PhotoEvent(
            id=1,
            event_time=datetime(2026, 9, 15, 10, 10, tzinfo=timezone.utc),
        )
        used_event_ids: set[int] = set()

        first_match = _find_closest_photo_event([event], time(10, 0), used_event_ids)
        self.assertIs(first_match, event)
        assert first_match is not None
        used_event_ids.add(first_match.id)

        second_match = _find_closest_photo_event([event], time(10, 30), used_event_ids)

        self.assertIsNone(second_match)


class AdherenceEvaluationTests(unittest.IsolatedAsyncioTestCase):
    async def test_inferences_are_fetched_in_one_batch_for_matched_events(self) -> None:
        today = date.today()
        first_event = PhotoEvent(id=1, event_time=datetime.combine(today, time(9, 5)))
        second_event = PhotoEvent(id=2, event_time=datetime.combine(today, time(10, 5)))
        schedules = [
            SimpleNamespace(id=1, time_of_day=time(9, 0)),
            SimpleNamespace(id=2, time_of_day=time(10, 0)),
        ]
        inferences = [
            SimpleNamespace(photo_event_id=1, state="changed", is_changed=True, confidence=0.9),
            SimpleNamespace(photo_event_id=1, state="changed", is_changed=True, confidence=0.9),
            SimpleNamespace(photo_event_id=2, state="unchanged", is_changed=False, confidence=0.6),
        ]
        existing_outcome = SimpleNamespace(
            schedule_id=1,
            status="unknown",
            confidence=0.0,
            photo_event_id=None,
            notes="old result",
        )
        db = SimpleNamespace(
            execute=AsyncMock(
                side_effect=[
                    _query_result(schedules),
                    _query_result([second_event, first_event]),
                    _query_result(inferences),
                    _query_result([existing_outcome]),
                ]
            ),
            add=Mock(),
            commit=AsyncMock(),
        )

        outcomes = await evaluate_from_photos(db, user_id=7)

        self.assertEqual(db.execute.await_count, 4)
        self.assertEqual(db.commit.await_count, 1)
        self.assertEqual(db.add.call_count, 1)
        self.assertEqual(len(outcomes), 2)
        self.assertIs(outcomes[0], existing_outcome)
        self.assertEqual(
            (existing_outcome.status, existing_outcome.confidence, existing_outcome.photo_event_id),
            ("taken", 0.9, first_event.id),
        )
        self.assertEqual(
            (outcomes[1].schedule_id, outcomes[1].status, outcomes[1].confidence, outcomes[1].photo_event_id),
            (2, "missed", 0.6, second_event.id),
        )


if __name__ == "__main__":
    unittest.main()
