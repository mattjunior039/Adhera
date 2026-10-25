import json
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from backend_api.database import Base, get_db
from backend_api.models.compartment_inventory import CompartmentInventory
from backend_api.models.dose_verification_event import DoseVerificationEvent
from backend_api.models.medication import Medication
from backend_api.models.pillbox_orientation_profile import PillboxOrientationProfile
from backend_api.models.user import User
from backend_api.routers import dose_verification as route
from backend_api.services import video_verification_service as service
from backend_api.services.official_video_detection import compare_target_medications
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine


def candidate_report(transfer=False):
    pre, post = [1] * 21, [1] * 21
    post[4] = 0
    if transfer:
        post[7] = 2
    return {
        **compare_target_medications([pre] * 4, [post] * 4),
        "compartment_index": 8,
        "assumed_label": "MON_PM",
        "pre_count": 1,
        "post_count": 0,
        "confidence": 1.0,
        "frames_sampled": 8,
        "frames_accepted": 8,
        "samples_total": 8,
        "samples_accepted": 8,
        "prototype": "official_blue_pm",
        "mode": "assisted_time_windows",
        "model_provenance": {"pills_sha256": "a" * 64, "compartments_sha256": "b" * 64},
    }


class VideoServiceTests(unittest.TestCase):
    def test_adapter_keeps_pm_indices_transfer_semantics_and_review(self):
        detector = MagicMock()
        detector.analyze.return_value = candidate_report(transfer=True)
        with patch.object(service, "_load_models", return_value=(detector, {"pills_sha256": "a" * 64})):
            result = service.analyze_dose_removal_video("video.mp4", windows=((1, 2), (4, 5)))
        self.assertEqual(result["compartment_index"], 8)
        self.assertEqual(result["event_type"], "CANDIDATE_TRANSFER")
        self.assertEqual(result["removed_count"], 0)
        self.assertTrue(result["requires_review"])
        detector.analyze.assert_called_once_with(
            Path("video.mp4"),
            windows=((1, 2), (4, 5)),
            fps=4,
            max_duration_seconds=120,
        )

    def test_busy_does_not_start_second_inference(self):
        with service._inference_lock:
            with self.assertRaises(service.VideoAnalysisBusy):
                service.analyze_dose_removal_video("video.mp4")

    def test_inference_failure_releases_lock(self):
        detector = MagicMock()
        detector.analyze.side_effect = RuntimeError("inference failed")
        with patch.object(service, "_load_models", return_value=(detector, {})):
            with self.assertRaisesRegex(RuntimeError, "inference failed"):
                service.analyze_dose_removal_video("video.mp4")
        self.assertFalse(service._inference_lock.locked())

    def test_missing_models_and_failed_load_do_not_poison_cache_or_lock(self):
        with tempfile.TemporaryDirectory() as root:
            with patch.dict(
                "os.environ",
                {
                    "OFFICIAL_PILL_CHECKPOINT": str(Path(root) / "missing.pt"),
                    "OFFICIAL_COMPARTMENT_CHECKPOINT": str(Path(root) / "missing-seg.pt"),
                },
            ):
                for _ in range(2):
                    with self.assertRaises(service.VideoModelUnavailable):
                        service.analyze_dose_removal_video("video.mp4")
        self.assertFalse(service._inference_lock.locked())


class VideoAPITests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.uploads = Path(self.directory.name)
        self.patch_uploads = patch.object(route, "UPLOAD_DIR", self.uploads)
        self.patch_uploads.start()
        self.engine = create_async_engine("sqlite+aiosqlite:///:memory:")
        async with self.engine.begin() as connection:
            await connection.run_sync(Base.metadata.create_all)
        self.sessions = async_sessionmaker(self.engine, expire_on_commit=False)
        async with self.sessions() as db:
            user = User(email="video-test@example.com", full_name="Video Test")
            other = User(email="other-video@example.com", full_name="Other")
            db.add_all([user, other])
            await db.flush()
            medication = Medication(user_id=user.id, name="Acetaminophen")
            db.add(medication)
            await db.flush()
            slot = CompartmentInventory(
                user_id=user.id,
                day_of_week="Friday",
                period="PM",
                medication_id=medication.id,
                pill_count=2,
            )
            db.add(slot)
            await db.commit()
            self.user_id, self.other_id, self.slot_id = user.id, other.id, slot.id

        async def test_db():
            async with self.sessions() as db:
                yield db

        app = FastAPI()
        app.include_router(route.router)
        app.dependency_overrides[get_db] = test_db
        self.client = AsyncClient(transport=ASGITransport(app=app), base_url="http://test")

    async def asyncTearDown(self):
        await self.client.aclose()
        await self.engine.dispose()
        self.patch_uploads.stop()
        self.directory.cleanup()

    async def upload(self, data=None, content=b"test-video"):
        return await self.client.post(
            "/dose-verification/analyze-video",
            data={"user_id": self.user_id, "compartment_id": self.slot_id, **(data or {})},
            files={"file": ("video.mp4", content, "video/mp4")},
        )

    async def test_threaded_inference_does_not_receive_expected_label_or_update_inventory(self):
        main_thread = threading.get_ident()

        def analyze(path, *, windows):
            self.assertNotEqual(threading.get_ident(), main_thread)
            self.assertTrue(path.is_file())
            self.assertEqual(windows, ((1.0, 2.0), (4.0, 5.0)))
            return candidate_report(transfer=True)

        with patch.object(route, "analyze_dose_removal_video", side_effect=analyze):
            response = await self.upload(
                {
                    "before_start": 1,
                    "before_end": 2,
                    "after_start": 4,
                    "after_end": 5,
                }
            )
        self.assertEqual(response.status_code, 200, response.text)
        payload = response.json()
        self.assertEqual(payload["event_type"], "CANDIDATE_TRANSFER")
        self.assertEqual(payload["destination_label"], "TUE_PM")
        self.assertEqual(payload["removed_count"], 0)
        self.assertTrue(payload["requires_review"])
        self.assertTrue(payload["wrong_slot"])
        self.assertEqual(payload["expected_label"], "FRI_PM")
        self.assertFalse(payload["orientation_calibrated"])
        self.assertFalse(payload["inventory_updated"])
        async with self.sessions() as db:
            slot = await db.get(CompartmentInventory, self.slot_id)
            assert slot is not None
            self.assertEqual(slot.pill_count, 2)
            self.assertEqual((await db.execute(select(PillboxOrientationProfile))).scalars().all(), [])
        history = await self.client.get(f"/dose-verification/{self.user_id}")
        self.assertEqual(history.status_code, 200, history.text)
        self.assertEqual(history.json(), [payload])
        evidence = json.loads(next(self.uploads.glob("*.analysis.json")).read_text())
        self.assertEqual(evidence["event_type"], "CANDIDATE_TRANSFER")

    async def test_invalid_intervals_empty_and_oversized_uploads_are_rejected_and_cleaned(self):
        with patch.object(route, "analyze_dose_removal_video") as analyze:
            for fields in (
                {"before_start": 1},
                {"before_start": "nan", "before_end": 2, "after_start": 4, "after_end": 5},
                {"before_start": 2, "before_end": 1, "after_start": 4, "after_end": 5},
            ):
                self.assertEqual((await self.upload(fields)).status_code, 400)
            self.assertEqual((await self.upload(content=b"")).status_code, 400)
            with patch.object(route, "MAX_UPLOAD_BYTES", 4):
                self.assertEqual((await self.upload(content=b"12345")).status_code, 413)
            analyze.assert_not_called()
        self.assertEqual(list(self.uploads.iterdir()), [])

    async def test_missing_model_busy_and_unreadable_video_have_explicit_errors(self):
        for failure, status in (
            (service.VideoModelUnavailable("models missing"), 503),
            (service.VideoAnalysisBusy("busy"), 503),
            (ValueError("invalid video"), 400),
        ):
            with patch.object(route, "analyze_dose_removal_video", side_effect=failure):
                response = await self.upload()
            self.assertEqual(response.status_code, status, response.text)
            self.assertEqual(list(self.uploads.iterdir()), [])
        async with self.sessions() as db:
            self.assertEqual((await db.execute(select(DoseVerificationEvent))).scalars().all(), [])

    async def test_foreign_compartment_is_rejected_before_analysis(self):
        with patch.object(route, "analyze_dose_removal_video") as analyze:
            response = await self.upload({"user_id": self.other_id})
            self.assertEqual(response.status_code, 404)
            analyze.assert_not_called()
        self.assertEqual(list(self.uploads.iterdir()), [])
