import csv
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from backend_api.scripts.training.prepare_official_prototype import (
    CLASS_NAMES,
    VIDEO_FIELDS,
    candidate_times,
    file_digest,
    prepare,
    write_csv,
)


class OfficialPrototypePreparationTests(unittest.TestCase):
    def test_candidates_cover_whole_clip_without_endpoints(self) -> None:
        times = candidate_times(24.0, 12)
        self.assertEqual(times, list(range(1, 24, 2)))
        self.assertEqual(len(times), 12)
        self.assertEqual(candidate_times(1.0, 2), [0.25, 0.75])

    def test_invalid_sampling_fails_explicitly(self) -> None:
        for duration in (0.0, -1.0, float("nan"), float("inf")):
            with self.subTest(duration=duration), self.assertRaises(ValueError):
                candidate_times(duration, 12)
        with self.assertRaises(ValueError):
            candidate_times(10.0, 1)

    def test_pill_class_order_does_not_mix_in_compartment_segmenter(self) -> None:
        self.assertEqual(CLASS_NAMES, ("acetaminophen", "ibuprofen", "iron"))

    def test_manifest_keeps_ground_truth_and_splits_unassigned(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.csv"
            write_csv(
                path,
                VIDEO_FIELDS,
                [
                    {
                        "video_id": "clip_001",
                        "source_filename": "clip, one.mp4",
                        "removed_count": 1,
                    }
                ],
            )
            with path.open(newline="") as source:
                row = next(csv.DictReader(source))
            self.assertEqual(row["source_filename"], "clip, one.mp4")
            self.assertEqual(row["removed_count"], "1")
            for field in ("session_id", "split", "removed_day", "removed_class"):
                self.assertEqual(row[field], "")

    def test_prepared_manifest_does_not_assume_every_clip_is_one_removal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / "source", root / "output"
            source.mkdir()
            (source / "fixture.mp4").write_bytes(b"recording fixture")
            module = "backend_api.scripts.training.prepare_official_prototype"
            with (
                patch(f"{module}.shutil.which", return_value="/mock/ffmpeg"),
                patch(
                    f"{module}.video_duration",
                    return_value=4.0,
                ),
                patch(
                    f"{module}.subprocess.run",
                    side_effect=lambda command, **kwargs: Path(command[-1]).write_bytes(b"frame fixture"),
                ),
                patch("builtins.print"),
            ):
                self.assertEqual(prepare(source, output, frames_per_video=2), (1, 2))
            with (output / "video_manifest.csv").open(newline="") as target:
                row = next(csv.DictReader(target))
            for field in (
                "removed_count",
                "event_type",
                "source_day",
                "destination_day",
                "transferred_class",
                "transferred_count",
            ):
                self.assertEqual(row[field], "")
            metadata = json.loads((output / "prototype.json").read_text())
            self.assertEqual(metadata["class_names"], list(CLASS_NAMES))
            self.assertEqual(metadata["compartment_annotation"]["format"], "COCO polygons")

    def test_digests_match_content_not_filename(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            first, second = Path(directory) / "a.mp4", Path(directory) / "b.mp4"
            first.write_bytes(b"same recording")
            second.write_bytes(b"same recording")
            self.assertEqual(file_digest(first), file_digest(second))

    def test_existing_output_is_not_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / "source", Path(directory) / "output"
            source.mkdir()
            output.mkdir()
            marker = output / "manual_labels.txt"
            marker.write_text("important annotations")
            with self.assertRaisesRegex(ValueError, "Output already exists"):
                prepare(source, output)
            self.assertEqual(marker.read_text(), "important annotations")

    def test_nested_paths_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            with self.assertRaisesRegex(ValueError, "not nested"):
                prepare(source, source / "output")

    def test_missing_media_tool_is_explicit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            source.mkdir()
            with (
                patch(
                    "backend_api.scripts.training.prepare_official_prototype.shutil.which",
                    return_value=None,
                ),
                self.assertRaisesRegex(ValueError, "ffmpeg is required"),
            ):
                prepare(source, Path(directory) / "output")


if __name__ == "__main__":
    unittest.main()
