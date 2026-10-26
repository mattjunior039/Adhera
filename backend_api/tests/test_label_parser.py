import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import cv2
import numpy as np

from backend_api.services import ocr_service
from backend_api.services.ocr_service import parse_label_text

LABEL = """CVS Pharmacy
1234 Main St, Springfield
Rx# 0123456  Date Filled: 10/02/2026
JANE DOE
IBUPROFEN 200 MG TABLET
TAKE 1 TABLET BY MOUTH
EVERY 6 HOURS AS NEEDED FOR PAIN
QTY: 30  Refills: 2
Dr. Maria Lopez
"""


class LabelParserTests(unittest.TestCase):
    def setUp(self) -> None:
        # Keep tests offline: RxNorm lookups fall back to the local dictionary.
        patcher = patch("backend_api.services.drug_dictionary.resolve_rxnorm", return_value=None)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_extracts_fields_from_pharmacy_label(self) -> None:
        result = parse_label_text(LABEL)
        self.assertEqual(result["medication_name"], "Ibuprofen")
        self.assertTrue(result["medication_name_matched"])
        self.assertEqual(result["dosage"].lower(), "200 mg")
        self.assertEqual(
            result["instructions"],
            "TAKE 1 TABLET BY MOUTH EVERY 6 HOURS AS NEEDED FOR PAIN",
        )
        self.assertEqual(result["refills_remaining"], "2")
        self.assertEqual(result["prescribed_by"], "Maria Lopez")
        self.assertEqual(result["pharmacy"], "CVS Pharmacy")
        self.assertFalse(result["requires_human_review"])

    def test_uses_rxnorm_match_when_available(self) -> None:
        # Rosuvastatin is not in the local dictionary, so the RxNorm result is used.
        rxnorm = {"name": "rosuvastatin", "score": 99.0, "source": "rxnorm_api", "rxcui": "301542"}
        with patch("backend_api.services.drug_dictionary.resolve_rxnorm", return_value=rxnorm):
            result = parse_label_text("ROSUVASTATIN 10MG TAB\nTake 1 tablet by mouth daily")
        self.assertEqual(result["medication_name"], "rosuvastatin")
        self.assertEqual(result["medication_name_source"], "rxnorm_api")
        self.assertEqual(result["medication_name_rxcui"], "301542")
        self.assertEqual(result["dosage"].lower(), "10mg")

    def test_no_refills_and_unknown_drug_require_review(self) -> None:
        result = parse_label_text("ZZQX 10 MG\nRefills: none")
        self.assertEqual(result["refills_remaining"], "0")
        self.assertFalse(result["medication_name_matched"])
        self.assertTrue(result["requires_human_review"])

    def test_empty_text_returns_blank_fields_for_manual_entry(self) -> None:
        result = parse_label_text("")
        self.assertEqual(result["medication_name"], "")
        self.assertEqual(result["instructions"], "")
        self.assertTrue(result["requires_human_review"])

    def test_full_scan_uses_google_cloud_vision_when_available(self) -> None:
        image = np.full((480, 640, 3), 235, dtype=np.uint8)
        cv2.rectangle(image, (120, 100), (520, 380), (255, 255, 255), -1)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "label.jpg"
            cv2.imwrite(str(path), image)
            with patch(
                "backend_api.services.ocr_service._ocr_with_google_vision",
                return_value={"full_text": LABEL, "focus_text": LABEL},
            ):
                result = ocr_service.scan_prescription_label_multi_views([path])
        self.assertEqual(result["medication_name"], "Ibuprofen")
        self.assertEqual(
            result["ocr_provider_chain"],
            ["google_cloud_vision_document", ocr_service.PARSER_NAME],
        )
        self.assertTrue(result["label_preview_base64"])

    def test_full_scan_falls_back_to_device_ocr_when_cloud_vision_unavailable(self) -> None:
        image = np.full((480, 640, 3), 235, dtype=np.uint8)
        cv2.rectangle(image, (120, 100), (520, 380), (255, 255, 255), -1)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "label.jpg"
            cv2.imwrite(str(path), image)
            with patch(
                "backend_api.services.ocr_service._ocr_with_google_vision",
                side_effect=RuntimeError("network unavailable"),
            ):
                result = ocr_service.scan_prescription_label_multi_views([path], LABEL, "apple_vision")
        self.assertEqual(result["medication_name"], "Ibuprofen")
        self.assertEqual(result["ocr_provider_chain"], ["apple_vision", ocr_service.PARSER_NAME])
        self.assertTrue(result["label_preview_base64"])


class QualityGateTests(unittest.TestCase):
    def test_skew_estimate_handles_detected_lines(self) -> None:
        image = np.full((400, 600, 3), 255, dtype=np.uint8)
        for offset in range(0, 300, 30):
            cv2.line(image, (50, 60 + offset), (550, 100 + offset), (0, 0, 0), 3)
        gate = ocr_service._quality_gate(image)
        self.assertGreater(gate["skew_degrees"], 0.0)


if __name__ == "__main__":
    unittest.main()
