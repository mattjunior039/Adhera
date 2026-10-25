from __future__ import annotations

import importlib
import json
import os
import tempfile
import unittest
from unittest.mock import patch

import backend_api.services.rxnorm_service as rxnorm_service


class RxNormServiceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.old_mode = os.environ.get("RXNORM_LOOKUP_MODE")
        self.old_local_path = os.environ.get("RXNORM_LOCAL_PATH")
        self.old_ttys = os.environ.get("RXNORM_ALLOWED_TTYS")

    def tearDown(self) -> None:
        if self.old_mode is None:
            os.environ.pop("RXNORM_LOOKUP_MODE", None)
        else:
            os.environ["RXNORM_LOOKUP_MODE"] = self.old_mode

        if self.old_local_path is None:
            os.environ.pop("RXNORM_LOCAL_PATH", None)
        else:
            os.environ["RXNORM_LOCAL_PATH"] = self.old_local_path

        if self.old_ttys is None:
            os.environ.pop("RXNORM_ALLOWED_TTYS", None)
        else:
            os.environ["RXNORM_ALLOWED_TTYS"] = self.old_ttys

        importlib.reload(rxnorm_service)

    def test_local_mode_uses_dataset(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tmp:
            json.dump(
                [
                    {"name": "Metformin", "rxcui": "6809"},
                    {"name": "Lisinopril", "rxcui": "29046"},
                ],
                tmp,
            )
            tmp_path = tmp.name

        os.environ["RXNORM_LOOKUP_MODE"] = "local"
        os.environ["RXNORM_LOCAL_PATH"] = tmp_path
        importlib.reload(rxnorm_service)

        result = rxnorm_service.resolve_rxnorm("metfornin", threshold=85.0)
        self.assertIsNotNone(result)
        assert result is not None
        self.assertEqual(result.get("name"), "Metformin")
        self.assertEqual(result.get("source"), "rxnorm_local")
        self.assertEqual(result.get("rxcui"), "6809")

    def test_both_mode_falls_back_to_api_when_local_missing(self) -> None:
        os.environ["RXNORM_LOOKUP_MODE"] = "both"
        os.environ["RXNORM_LOCAL_PATH"] = "/tmp/does-not-exist-rxnorm.json"
        importlib.reload(rxnorm_service)

        with patch.object(
            rxnorm_service,
            "api_rxnorm_match",
            return_value={
                "name": "Metformin",
                "rxcui": "6809",
                "score": 93.0,
                "source": "rxnorm_api",
            },
        ) as mocked_api:
            result = rxnorm_service.resolve_rxnorm("metfornin", threshold=85.0)

        mocked_api.assert_called_once()
        self.assertIsNotNone(result)
        assert result is not None
        self.assertEqual(result.get("source"), "rxnorm_api")
        self.assertEqual(result.get("rxcui"), "6809")

    def test_local_mode_respects_allowed_tty_scope(self) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tmp:
            json.dump(
                [
                    {"name": "Daily", "rxcui": "111", "tty": "DF"},
                    {"name": "Metformin", "rxcui": "6809", "tty": "IN"},
                ],
                tmp,
            )
            tmp_path = tmp.name

        os.environ["RXNORM_LOOKUP_MODE"] = "local"
        os.environ["RXNORM_LOCAL_PATH"] = tmp_path
        os.environ["RXNORM_ALLOWED_TTYS"] = "SCD,SBD,IN,BN"
        importlib.reload(rxnorm_service)

        blocked = rxnorm_service.resolve_rxnorm("daily", threshold=85.0)
        self.assertIsNone(blocked)

        allowed = rxnorm_service.resolve_rxnorm("metformin", threshold=85.0)
        self.assertIsNotNone(allowed)
        assert allowed is not None
        self.assertEqual(allowed.get("name"), "Metformin")


if __name__ == "__main__":
    unittest.main()
