from __future__ import annotations

import unittest
from unittest.mock import patch

try:
    import backend_api.services.drug_dictionary as drug_dictionary
except ImportError:
    import services.drug_dictionary as drug_dictionary


class DrugDictionaryGuardrailTests(unittest.TestCase):
    def test_instruction_text_is_blocked_before_matching(self) -> None:
        result = drug_dictionary.validate_drug_name("DAILY AS NEEDED")
        self.assertEqual(result.matched, False)
        self.assertEqual(result.source, "blocked_stopwords")
        self.assertEqual(result.score, 0.0)

    def test_prescriber_line_is_blocked_before_matching(self) -> None:
        result = drug_dictionary.validate_drug_name("DR. NOAH LOTT")
        self.assertEqual(result.matched, False)
        self.assertEqual(result.source, "blocked_stopwords")

    def test_typo_medication_still_matches_local_dictionary(self) -> None:
        with patch.object(drug_dictionary, "resolve_rxnorm", return_value=None):
            result = drug_dictionary.validate_drug_name("metfornin")
        self.assertEqual(result.matched, True)
        self.assertEqual(result.snapped_name, "Metformin")


if __name__ == "__main__":
    unittest.main()