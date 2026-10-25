from __future__ import annotations

import unittest

import cv2
import numpy as np

from backend_api.services.ocr_service import (
    _warp_label_region,
    compose_flattened_label_from_images,
)


class OcrServiceParsingTests(unittest.TestCase):
    def test_warp_label_region_flattens_rotated_label_contour(self) -> None:
        img = np.zeros((720, 1200, 3), dtype=np.uint8)
        box = cv2.boxPoints(((600, 360), (720, 240), 14))
        box = np.int32(box)
        cv2.drawContours(img, [box], 0, (255, 255, 255), thickness=-1)
        cv2.putText(img, "Metformin", (385, 360), cv2.FONT_HERSHEY_SIMPLEX, 2.0, (0, 0, 0), 4, cv2.LINE_AA)

        warped, meta = _warp_label_region(img)

        self.assertTrue(bool(meta.get("flattened")))
        self.assertEqual(meta.get("label_region_reason"), "warped")
        self.assertGreater(warped.shape[1], warped.shape[0])
        self.assertLess(warped.shape[1], img.shape[1])

    def test_compose_flattened_label_from_images_uses_multiple_frames(self) -> None:
        frame_left = np.zeros((720, 1200, 3), dtype=np.uint8)
        left_box = cv2.boxPoints(((520, 360), (700, 240), 12))
        cv2.drawContours(frame_left, [np.int32(left_box)], 0, (255, 255, 255), thickness=-1)
        cv2.putText(frame_left, "LEFT", (360, 360), cv2.FONT_HERSHEY_SIMPLEX, 2.2, (0, 0, 0), 5, cv2.LINE_AA)

        frame_right = np.zeros((720, 1200, 3), dtype=np.uint8)
        right_box = cv2.boxPoints(((680, 360), (700, 240), -11))
        cv2.drawContours(frame_right, [np.int32(right_box)], 0, (255, 255, 255), thickness=-1)
        cv2.putText(
            frame_right, "RIGHT", (540, 360), cv2.FONT_HERSHEY_SIMPLEX, 2.0, (0, 0, 0), 5, cv2.LINE_AA
        )

        composite, meta = compose_flattened_label_from_images([frame_left, frame_right])

        self.assertTrue(bool(meta.get("composite")))
        self.assertEqual(meta.get("source_frames"), 2)
        self.assertEqual(meta.get("used_frames"), 2)
        self.assertGreater(composite.shape[0], 50)
        self.assertGreater(composite.shape[1], 100)


if __name__ == "__main__":
    unittest.main()
