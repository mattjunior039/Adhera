import os
import tempfile
import unittest
from unittest.mock import patch

import cv2
import numpy as np
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from backend_api.routers import pill_analysis
from backend_api.services import pill_vision


def _jpeg() -> bytes:
    ok, buffer = cv2.imencode(".jpg", np.zeros((8, 8, 3), dtype=np.uint8))
    assert ok
    return buffer.tobytes()


class PillAnalyzeApiTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        app = FastAPI()
        app.include_router(pill_analysis.router)
        self.client = AsyncClient(transport=ASGITransport(app=app), base_url="http://test")
        pill_vision._local_model = None

    async def asyncTearDown(self) -> None:
        await self.client.aclose()
        pill_vision._local_model = None

    async def test_missing_detector_weights_return_service_unavailable(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            missing = os.path.join(tmp, "missing.pt")
            with patch.dict(os.environ, {"PILL_DETECTION_MODEL_PATH": missing}):
                response = await self.client.post(
                    "/pills/analyze", files={"file": ("pill.jpg", _jpeg(), "image/jpeg")}
                )
        self.assertEqual(response.status_code, 503)
        self.assertIn("PILL_DETECTION_MODEL_PATH", response.json()["detail"])

    async def test_invalid_image_is_rejected_before_loading_model(self) -> None:
        with patch.object(pill_vision, "_get_model", side_effect=AssertionError("model loaded")):
            response = await self.client.post(
                "/pills/analyze", files={"file": ("pill.jpg", b"not an image", "image/jpeg")}
            )
        self.assertEqual(response.status_code, 400)


if __name__ == "__main__":
    unittest.main()
