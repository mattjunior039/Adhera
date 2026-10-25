import unittest

from backend_api.services.pill_reference_service import match_pill_signature


class PillReferenceMatchingTests(unittest.TestCase):
    def test_returns_closest_labeled_reference_and_requires_review(self) -> None:
        result = match_pill_signature(
            [1.0, 0.0],
            {
                "Acetaminophen": [[0.8, 0.2], [1.0, 0.0]],
                "Ibuprofen": [[0.0, 1.0]],
            },
        )

        self.assertEqual(result["medication_name"], "Acetaminophen")
        self.assertEqual(result["similarity"], 1.0)
        self.assertTrue(result["requires_review"])

    def test_rejects_unusable_signature(self) -> None:
        with self.assertRaises(ValueError):
            match_pill_signature([0.0, 0.0], {"Acetaminophen": [[1.0, 0.0]]})


if __name__ == "__main__":
    unittest.main()
