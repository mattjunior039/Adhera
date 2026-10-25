import argparse
import json
import tempfile
import unittest
from pathlib import Path

from backend_api.scripts.training.official_detector import (
    compare_images,
    prepare_dataset,
    read_labels,
)
from backend_api.services.official_pill_detection import compare_counts


class OfficialCountComparisonTests(unittest.TestCase):
    def test_exact_single_class_delta_is_review_only(self) -> None:
        result = compare_counts([[2, 3, 1]] * 2, [[2, 2, 1]] * 2)
        self.assertEqual(result["event_type"], "CANDIDATE_SINGLE_REMOVAL")
        self.assertEqual(result["medication_class"], "ibuprofen")
        self.assertEqual(result["removed_count"], 1)
        self.assertTrue(result["requires_review"])

    def test_iron_removal(self) -> None:
        result = compare_counts([[1, 1, 2]] * 3, [[1, 1, 1]] * 3)
        self.assertEqual(result["medication_class"], "iron")

    def test_unchanged_counts_do_not_claim_verified_removal(self) -> None:
        result = compare_counts([[1, 2, 3]] * 2, [[1, 2, 3]] * 2)
        self.assertEqual(result["event_type"], "NO_COUNT_CHANGE")
        self.assertIsNone(result["removed_count"])
        self.assertTrue(result["requires_review"])

    def test_disagreement_or_insufficient_views_abstains(self) -> None:
        for before, after in (
            ([], []),
            ([[1, 2, 3]], [[1, 1, 3]] * 2),
            ([[1, 2, 3], [0, 2, 3]], [[1, 1, 3]] * 2),
            ([[1, 2, 3]] * 2, [[1, 1, 3], [1, 2, 3]]),
        ):
            with self.subTest(before=before, after=after):
                self.assertEqual(compare_counts(before, after)["event_type"], "INCONCLUSIVE")

    def test_additions_and_multiple_changes_abstain(self) -> None:
        for after in ([2, 3, 3], [1, 1, 3], [0, 2, 3], [1, 3, 3]):
            with self.subTest(after=after):
                self.assertEqual(
                    compare_counts([[2, 2, 3]] * 2, [after] * 2)["event_type"],
                    "INCONCLUSIVE",
                )

    def test_invalid_counts_raise(self) -> None:
        for counts in ([1, -1, 0], [1, 2], [True, 1, 1], [1.0, 1, 1]):
            with self.subTest(counts=counts), self.assertRaises(ValueError):
                compare_counts([counts] * 2, [[0, 0, 0]] * 2)


class OfficialDatasetTests(unittest.TestCase):
    def test_invalid_yolo_rows_raise(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "labels.txt"
            for line in (
                "0 0.5 0.5 0.1",
                "3 0.5 0.5 0.1 0.1",
                "0 nan 0.5 0.1 0.1",
                "1 0.5 0.5 0.1 0",
                "1 0.99 0.5 0.2 0.1",
            ):
                path.write_text(line)
                with self.subTest(line=line), self.assertRaises(ValueError):
                    read_labels(path)

    def test_zero_area_exclusion_is_opt_in_and_audited(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "labels.txt"
            path.write_text("2 0.5 0.5 0.1 0\n0 0.5 0.5 0.2 0.2\n")
            original = path.read_bytes()
            exclusions: list[str] = []
            boxes = read_labels(path, drop_zero_area=True, exclusions=exclusions)
            self.assertEqual(len(boxes), 1)
            self.assertEqual(len(exclusions), 1)
            self.assertIn("labels.txt:1", exclusions[0])
            self.assertEqual(path.read_bytes(), original)

    def make_sources(self, directory: str) -> tuple[Path, Path, Path]:
        root = Path(directory)
        labels, images = root / "input_labels", root / "input_images"
        labels.mkdir()
        images.mkdir()
        content = "0 0.2 0.5 0.1 0.1\n1 0.5 0.5 0.1 0.1\n2 0.8 0.5 0.1 0.1\n"
        for clip in ("001", "002"):
            stem = f"clip_{clip}_frame_001"
            (labels / f"{stem}.txt").write_text(content)
            (images / f"{stem}.jpg").write_bytes(clip.encode())
        (images / "clip_003_frame_001.jpg").write_bytes(b"unlabeled")
        return labels, images, root / "dataset"

    def test_only_labeled_images_are_copied_and_clips_are_disjoint(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            labels, images, output = self.make_sources(directory)
            report = prepare_dataset(labels, images, output, {"clip_002"})
            self.assertEqual(report["annotated_images"], 2)
            self.assertEqual(len(list((output / "images" / "train").glob("*.jpg"))), 1)
            self.assertTrue((output / "images/val/clip_002_frame_001.jpg").is_file())
            self.assertFalse(list(output.rglob("clip_003*")))
            specification = json.loads((output / "dataset.yaml").read_text())
            self.assertEqual(specification["names"], ["acetaminophen", "ibuprofen", "iron"])
            with self.assertRaisesRegex(ValueError, "overwrite"):
                prepare_dataset(labels, images, output, {"clip_002"})

    def test_duplicate_content_between_clips_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            labels, images, output = self.make_sources(directory)
            (images / "clip_002_frame_001.jpg").write_bytes(b"001")
            with self.assertRaisesRegex(ValueError, "Duplicate image"):
                prepare_dataset(labels, images, output, {"clip_002"})
            self.assertFalse(output.exists())

    def test_missing_image_or_class_does_not_create_dataset(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            labels, images, output = self.make_sources(directory)
            (labels / "clip_002_frame_001.txt").write_text("1 0.5 0.5 0.1 0.1\n")
            with self.assertRaisesRegex(ValueError, "all three classes"):
                prepare_dataset(labels, images, output, {"clip_002"})
            self.assertFalse(output.exists())
            (images / "clip_002_frame_001.jpg").unlink()
            with self.assertRaisesRegex(ValueError, "No matching image"):
                prepare_dataset(labels, images, output, {"clip_002"})

    def test_unknown_validation_clip_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            labels, images, output = self.make_sources(directory)
            with self.assertRaisesRegex(ValueError, "must name annotated clips"):
                prepare_dataset(labels, images, output, {"clip_099"})
            self.assertFalse(output.exists())


class OfficialInferenceInputTests(unittest.TestCase):
    def test_clear_views_must_be_reviewed_explicitly(self) -> None:
        with self.assertRaisesRegex(ValueError, "Manually review"):
            compare_images(argparse.Namespace(confirmed_clear_views=False))

    def test_repeated_views_are_rejected_before_loading_model(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "image.jpg"
            image.write_bytes(b"same image")
            args = argparse.Namespace(
                confirmed_clear_views=True,
                before=[image, image],
                after=[image, image],
                confidence=0.5,
            )
            with self.assertRaisesRegex(ValueError, "distinct images"):
                compare_images(args)


if __name__ == "__main__":
    unittest.main()
