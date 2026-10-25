import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import cv2
import numpy as np

from backend_api.scripts.training.evaluate_official_videos import main as evaluate_main
from backend_api.scripts.training.evaluate_official_videos import summarize
from backend_api.scripts.training.official_compartments import prepare
from backend_api.services.official_video_detection import (
    Box,
    OfficialVideoDetector,
    compare_compartments,
    compare_target_medications,
    compartment_counts,
    order_compartments,
    phase_consensus,
)


def seven_cells() -> list[Box]:
    return [Box(0, 0.9, (i * 10.0, 0.0, i * 10.0 + 8.0, 20.0)) for i in range(7)]


class CompartmentAssignmentTests(unittest.TestCase):
    def test_left_to_right_order_is_not_detection_order(self) -> None:
        cells = seven_cells()
        self.assertEqual(order_compartments(list(reversed(cells))), cells)

    def test_incomplete_duplicate_and_invalid_geometry_abstains(self) -> None:
        cells = seven_cells()
        self.assertIsNone(order_compartments(cells[:-1]))
        self.assertIsNone(order_compartments(cells + [cells[0]]))
        self.assertIsNone(order_compartments([cells[0]] * 7))
        cells[0] = Box(0, 1.0, (float("nan"), 0.0, 3.0, 10.0))
        self.assertIsNone(order_compartments(cells))

    def test_assigns_each_pill_to_day_and_class(self) -> None:
        cells = seven_cells()
        pills = [Box(2, 0.8, (11.0, 3.0, 13.0, 7.0)), Box(0, 0.9, (61.0, 2.0, 63.0, 4.0))]
        counts = compartment_counts(list(reversed(cells)), pills)
        self.assertEqual(counts[1 * 3 + 2], 1)
        self.assertEqual(counts[6 * 3], 1)
        self.assertEqual(sum(counts), 2)

    def test_pills_outside_layout_do_not_silently_disappear(self) -> None:
        self.assertIsNone(compartment_counts(seven_cells(), [Box(0, 0.9, (100, 0, 102, 2))]))

    def test_unknown_class_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            compartment_counts(seven_cells(), [Box(3, 0.9, (1, 1, 3, 3))])

    def test_polygon_assignment_resolves_overlapping_bounding_rectangles(self) -> None:
        cells = seven_cells()
        cells[0] = Box(0, 0.9, (0, 0, 14, 20), ((0, 0), (8, 0), (14, 20), (6, 20)))
        cells[1] = Box(0, 0.9, (8, 0, 22, 20), ((10, 0), (18, 0), (22, 20), (16, 20)))
        # Center (12, 18) is in both rectangles but only the first polygon.
        counts = compartment_counts(cells, [Box(1, 0.9, (11, 17, 13, 19))])
        self.assertIsNotNone(counts)
        self.assertEqual(counts[1], 1)
        self.assertEqual(counts[4], 0)


class VideoConsensusTests(unittest.TestCase):
    def test_joint_consensus_requires_repeated_complete_vectors(self) -> None:
        a, b = [0] * 21, [0] * 21
        b[0] = 1
        value, agreement = phase_consensus([a, a, a, b])
        self.assertEqual(value, tuple(a))
        self.assertEqual(agreement, 0.75)
        self.assertIsNone(phase_consensus([a, a])[0])
        self.assertIsNone(phase_consensus([a, a, b, b])[0])

    def test_no_synthetic_per_cell_majority(self) -> None:
        frames = [[0] * 21 for _ in range(3)]
        for index, frame in enumerate(frames):
            frame[index] = 1
        self.assertIsNone(phase_consensus(frames)[0])

    def test_unique_change_reports_actual_day_without_expected_input(self) -> None:
        pre, post = [0] * 21, [0] * 21
        pre[5 * 3 + 1] = 1
        result = compare_compartments([pre] * 3, [post] * 3)
        self.assertEqual(result["day"], "FRI")
        self.assertEqual(result["medication_class"], "ibuprofen")
        self.assertEqual(result["removed_count"], 1)
        self.assertTrue(result["requires_review"])

    def test_unchanged_added_multiple_and_missing_views(self) -> None:
        zero = [0] * 21
        self.assertEqual(compare_compartments([zero] * 3, [zero] * 3)["event_type"], "NO_COUNT_CHANGE")
        self.assertEqual(compare_compartments([], [])["event_type"], "INCONCLUSIVE")
        changed = zero.copy()
        changed[1], changed[4] = 1, 1
        self.assertEqual(compare_compartments([changed] * 3, [zero] * 3)["event_type"], "INCONCLUSIVE")
        self.assertEqual(compare_compartments([zero] * 3, [changed] * 3)["event_type"], "INCONCLUSIVE")

    def test_invalid_count_vectors_raise(self) -> None:
        for bad in ([0] * 20, [-1] + [0] * 20, [True] + [0] * 20):
            with self.assertRaises(ValueError):
                phase_consensus([bad] * 3)

    def test_transfer_preserves_class_and_is_not_reported_as_pill_taken(self) -> None:
        pre, post = [0] * 21, [0] * 21
        pre[3 * 3 + 1], post[2 * 3 + 1] = 1, 1
        result = compare_compartments([pre] * 3, [post] * 3)
        self.assertEqual(result["event_type"], "CANDIDATE_TRANSFER")
        self.assertEqual(result["day"], "WED")
        self.assertEqual(result["destination_day"], "TUE")
        self.assertEqual(result["medication_class"], "ibuprofen")
        self.assertEqual(result["removed_count"], 0)
        self.assertEqual(result["transferred_count"], 1)
        self.assertTrue(result["requires_review"])

    def test_different_class_exchange_does_not_become_transfer(self) -> None:
        pre, post = [0] * 21, [0] * 21
        pre[3 * 3 + 1], post[2 * 3 + 2] = 1, 1
        result = compare_compartments([pre] * 3, [post] * 3)
        self.assertEqual(result["event_type"], "INCONCLUSIVE")


class TargetMedicationTests(unittest.TestCase):
    def phases(self):
        before = [[1] * 21 for _ in range(4)]
        after = [[1] * 21 for _ in range(4)]
        for index in range(4):
            before[index][2] = index
            after[index][2] = 4 - index
        return before, after

    def test_target_removal_survives_iron_noise_with_explicit_scope(self):
        for pill in (0, 1):
            before, after = self.phases()
            for frame in after:
                frame[3 + pill] = 0
            result = compare_target_medications(before, after)
            self.assertEqual(result["event_type"], "CANDIDATE_SINGLE_REMOVAL")
            self.assertEqual(result["day"], "MON")
            self.assertEqual(result["medication_class"], ("acetaminophen", "ibuprofen")[pill])
            self.assertEqual(result["evidence_scope"], "acetaminophen_ibuprofen_only")
            self.assertTrue(result["requires_review"])
            self.assertEqual(compare_compartments(before, after)["event_type"], "INCONCLUSIVE")

    def test_transfer_is_not_net_removal(self):
        before, after = self.phases()
        for frame in after:
            frame[10], frame[7] = 0, 2
        result = compare_target_medications(before, after)
        self.assertEqual(result["event_type"], "CANDIDATE_TRANSFER")
        self.assertEqual(result["day"], "WED")
        self.assertEqual(result["destination_day"], "TUE")
        self.assertEqual(result["removed_count"], 0)

    def test_competing_changes_and_additions_veto(self):
        for change in (-1, 1):
            before, after = self.phases()
            for frame in after:
                frame[3] = 0
                frame[4] += change
            self.assertEqual(compare_target_medications(before, after)["event_type"], "INCONCLUSIVE")

    def test_insufficient_or_synthetic_target_evidence_abstains(self):
        before, after = self.phases()
        for index, frame in enumerate(before):
            frame[3 * index] = 2
        for frame in after:
            frame[0] = 0
        self.assertEqual(compare_target_medications(before, after)["event_type"], "INCONCLUSIVE")
        self.assertEqual(compare_target_medications(before[:2], after[:2])["event_type"], "INCONCLUSIVE")
        self.assertEqual(compare_target_medications([], [])["event_type"], "INCONCLUSIVE")

    def test_iron_only_change_is_not_claimed_as_verified(self):
        before, after = self.phases()
        result = compare_target_medications(before, after)
        self.assertEqual(result["event_type"], "NO_COUNT_CHANGE")
        self.assertIsNone(result["removed_count"])
        self.assertIn("iron not verified", result["reason"])


class EvaluationMetricTests(unittest.TestCase):
    def test_abstentions_stay_in_accuracy_denominator(self) -> None:
        good = {
            "event_type": "CANDIDATE_SINGLE_REMOVAL",
            "day": "MON",
            "medication_class": "acetaminophen",
            "removed_count": 1,
            "expected_day": "MON",
            "expected_class": "acetaminophen",
            "expected_event_type": "SINGLE_REMOVAL",
        }
        wrong = {**good, "day": "TUE"}
        abstain = {**good, "event_type": "INCONCLUSIVE", "day": None}
        result = summarize([good, wrong, abstain, abstain])
        self.assertEqual(result["exact_accuracy_percent"], 25.0)
        self.assertEqual(result["coverage_percent"], 50.0)
        self.assertEqual(result["candidate_precision_percent"], 50.0)
        self.assertEqual(result["incorrect_candidates"], 1)

    def test_no_predictions_do_not_produce_perfect_precision(self) -> None:
        result = summarize(
            [
                {
                    "event_type": "INCONCLUSIVE",
                    "expected_event_type": "SINGLE_REMOVAL",
                }
            ]
        )
        self.assertEqual(result["exact_accuracy_percent"], 0.0)
        self.assertIsNone(result["candidate_precision_percent"])
        self.assertIsNone(summarize([])["exact_accuracy_percent"])

    def test_removals_and_transfers_have_separate_denominators(self) -> None:
        transfer = {
            "event_type": "CANDIDATE_TRANSFER",
            "day": "WED",
            "destination_day": "TUE",
            "medication_class": "ibuprofen",
            "removed_count": 0,
            "transferred_count": 1,
            "expected_day": "WED",
            "expected_class": "ibuprofen",
            "expected_event_type": "TRANSFER",
            "expected_destination_day": "TUE",
        }
        abstain = {"event_type": "INCONCLUSIVE", "expected_event_type": "SINGLE_REMOVAL"}
        result = summarize([transfer, abstain, abstain, abstain])
        self.assertEqual(result["exact_accuracy_percent"], 25.0)
        self.assertEqual(result["single_removal_success_percent"], 0.0)
        self.assertEqual(result["transfer_success_percent"], 100.0)
        wrong = summarize([{**transfer, "event_type": "CANDIDATE_SINGLE_REMOVAL", "removed_count": 1}])
        self.assertEqual(wrong["exact_accuracy_percent"], 0.0)
        wrong_destination = summarize([{**transfer, "destination_day": "FRI"}])
        self.assertEqual(wrong_destination["exact_accuracy_percent"], 0.0)

    def test_cli_keeps_ground_truth_out_of_inference_and_records_provenance(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cases, pills, cells = root / "cases.json", root / "pills.pt", root / "cells.pt"
            pills.write_bytes(b"pill checkpoint fixture")
            cells.write_bytes(b"compartment checkpoint fixture")
            case = {
                "clip": "fixture",
                "video": str(root / "fixture.mp4"),
                "expected_day": "MON",
                "expected_class": "acetaminophen",
                "expected_event_type": "SINGLE_REMOVAL",
                "windows": [[1.0, 2.0], [5.0, 6.0]],
                "pill_training_overlap": False,
                "compartment_training_overlap": False,
            }
            detector = MagicMock()
            detector.analyze.side_effect = lambda video, windows, fps: {
                "mode": "assisted_time_windows" if windows else "automatic",
                "event_type": "CANDIDATE_SINGLE_REMOVAL",
                "day": "FRI",
                "medication_class": "ibuprofen",
                "removed_count": 1,
                "samples_total": 10,
                "samples_accepted": 8,
            }
            for index, expected in enumerate(
                (
                    case,
                    {
                        **case,
                        "expected_day": "FRI",
                        "expected_class": "ibuprofen",
                    },
                )
            ):
                cases.write_text(json.dumps([expected]))
                output = root / f"report_{index}.json"
                with (
                    patch(
                        "backend_api.scripts.training.evaluate_official_videos.OfficialVideoDetector",
                        return_value=detector,
                    ),
                    patch(
                        "sys.argv",
                        [
                            "evaluate",
                            "--cases",
                            str(cases),
                            "--pill-checkpoint",
                            str(pills),
                            "--compartment-checkpoint",
                            str(cells),
                            "--output",
                            str(output),
                            "--comparison",
                            "target",
                            "--sample-fps",
                            "4",
                        ],
                    ),
                    patch("builtins.print"),
                ):
                    self.assertEqual(evaluate_main(), 0)
                result = json.loads(output.read_text())
                self.assertEqual(
                    result["summary"]["automatic"]["exact_accuracy_percent"],
                    0.0 if index == 0 else 100.0,
                )
                self.assertEqual(len(result["inputs"]["pill_checkpoint"]["sha256"]), 64)
                self.assertEqual(result["results"][0]["day"], "FRI")
                self.assertEqual(result["comparison"], "target")
                self.assertEqual(result["sample_fps"], 4.0)
            for invocation in detector.analyze.call_args_list:
                self.assertEqual(set(invocation.kwargs), {"windows", "fps"})
                self.assertEqual(invocation.kwargs["fps"], 4.0)
                self.assertEqual(invocation.args, (Path(case["video"]),))


class VideoSamplingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.detector = OfficialVideoDetector.__new__(OfficialVideoDetector)
        self.detector.comparison = "strict"
        self.capture = MagicMock()
        self.capture.isOpened.return_value = True
        self.capture.get.side_effect = lambda key: {
            cv2.CAP_PROP_FPS: 10.0,
            cv2.CAP_PROP_FRAME_COUNT: 100.0,
        }[key]
        self.capture.read.return_value = (True, np.zeros((4, 4, 3), dtype=np.uint8))

    def test_samples_entire_video_and_selects_disjoint_readable_windows(self) -> None:
        with (
            patch(
                "backend_api.services.official_video_detection.cv2.VideoCapture", return_value=self.capture
            ),
            patch.object(
                self.detector,
                "inspect_frame",
                return_value={"accepted": True, "counts": [0] * 21},
            ),
        ):
            report = self.detector.analyze(Path("fixture.mp4"))
        self.assertEqual(report["samples_total"], 20)
        self.assertEqual(report["before_seconds"], [0.0, 0.5, 1.0, 1.5])
        self.assertEqual(report["after_seconds"], [8.0, 8.5, 9.0, 9.5])
        self.assertEqual(report["event_type"], "NO_COUNT_CHANGE")
        self.capture.set.assert_called_with(cv2.CAP_PROP_POS_MSEC, 9500.0)
        self.capture.release.assert_called_once()

    def test_api_duration_limit_rejects_before_reading_and_releases_capture(self):
        with patch(
            "backend_api.services.official_video_detection.cv2.VideoCapture", return_value=self.capture
        ):
            with self.assertRaisesRegex(ValueError, "5-second limit"):
                self.detector.analyze(Path("fixture.mp4"), max_duration_seconds=5)
        self.capture.read.assert_not_called()
        self.capture.release.assert_called_once()

    def test_target_scope_remains_explicit_when_readable_windows_overlap(self):
        self.detector.comparison = "target"
        self.capture.get.side_effect = lambda key: 10.0 if key == cv2.CAP_PROP_FPS else 20.0
        with (
            patch(
                "backend_api.services.official_video_detection.cv2.VideoCapture", return_value=self.capture
            ),
            patch.object(
                self.detector,
                "inspect_frame",
                return_value={"accepted": True, "counts": [0] * 21},
            ),
        ):
            report = self.detector.analyze(Path("fixture.mp4"))
        self.assertEqual(report["event_type"], "INCONCLUSIVE")
        self.assertEqual(report["evidence_scope"], "acetaminophen_ibuprofen_only")

    def test_failed_decodes_are_explicit_not_empty_compartments(self) -> None:
        self.capture.read.return_value = (False, None)
        with patch(
            "backend_api.services.official_video_detection.cv2.VideoCapture", return_value=self.capture
        ):
            report = self.detector.analyze(Path("fixture.mp4"))
        self.assertEqual(report["event_type"], "INCONCLUSIVE")
        self.assertEqual(report["rejections"], {"decode_failed": 20})
        self.assertEqual(report["samples_accepted"], 0)
        self.capture.release.assert_called_once()

    def test_invalid_timing_and_overlapping_windows_raise_and_release(self) -> None:
        with patch(
            "backend_api.services.official_video_detection.cv2.VideoCapture", return_value=self.capture
        ):
            with self.assertRaisesRegex(ValueError, "ordered, disjoint"):
                self.detector.analyze(Path("fixture.mp4"), windows=((1, 4), (3, 6)))
            self.capture.release.assert_called_once()
            self.capture.release.reset_mock()
            self.capture.get.side_effect = lambda key: 10.0 if key == cv2.CAP_PROP_FPS else float("inf")
            with self.assertRaisesRegex(ValueError, "invalid frame timing"):
                self.detector.analyze(Path("fixture.mp4"))
            self.capture.release.assert_called_once()

    def test_same_readable_frames_cannot_be_both_before_and_after(self) -> None:
        self.capture.get.side_effect = lambda key: 10.0 if key == cv2.CAP_PROP_FPS else 20.0
        with (
            patch(
                "backend_api.services.official_video_detection.cv2.VideoCapture", return_value=self.capture
            ),
            patch.object(
                self.detector,
                "inspect_frame",
                return_value={"accepted": True, "counts": [0] * 21},
            ),
        ):
            report = self.detector.analyze(Path("fixture.mp4"))
        self.assertEqual(report["event_type"], "INCONCLUSIVE")
        self.assertEqual(report["reason"], "Readable before/after windows overlap.")


class PolygonExportTests(unittest.TestCase):
    def test_coco_categories_are_resolved_by_name_not_assumed_zero_id(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            images = root / "images"
            images.mkdir()
            rows = []
            annotations = []
            for index, clip in enumerate(("001", "002"), start=1):
                name = f"clip_{clip}_frame_001.jpg"
                (images / name).write_bytes(b"fixture")
                rows.append({"id": index, "file_name": name, "width": 100, "height": 100})
                for col in range(7):
                    x = col * 10
                    annotations.append(
                        {
                            "image_id": index,
                            "category_id": 4,
                            "segmentation": [[x, 0, x + 8, 0, x + 8, 20, x, 20]],
                        }
                    )
            coco = root / "export.json"
            coco.write_text(
                json.dumps(
                    {
                        "images": rows,
                        "annotations": annotations,
                        "categories": [{"id": 4, "name": "compartment"}],
                    }
                )
            )
            output = root / "dataset"
            report = prepare(coco, images, output)
            self.assertEqual(len(report["images"]), 2)
            lines = (output / "labels/train/clip_001_frame_001.txt").read_text().splitlines()
            self.assertEqual(len(lines), 7)
            self.assertEqual(len(lines[0].split()), 9)
            self.assertEqual(lines[0].split()[0], "0")
            with self.assertRaisesRegex(ValueError, "already exists"):
                prepare(coco, images, output)

    def test_incomplete_compartment_images_are_excluded_and_audited(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            images = root / "images"
            images.mkdir()
            rows, annotations = [], []
            for index, count in enumerate((7, 7, 6), start=1):
                name = f"clip_{'002' if index == 2 else '001'}_frame_{index:03d}.jpg"
                (images / name).write_bytes(b"fixture")
                rows.append({"id": index, "file_name": name, "width": 100, "height": 100})
                annotations.extend(
                    {
                        "image_id": index,
                        "category_id": 4,
                        "segmentation": [[col * 10, 0, col * 10 + 8, 0, col * 10 + 8, 20, col * 10, 20]],
                    }
                    for col in range(count)
                )
            coco = root / "export.json"
            coco.write_text(
                json.dumps(
                    {
                        "images": rows,
                        "annotations": annotations,
                        "categories": [{"id": 4, "name": "compartment"}],
                    }
                )
            )
            output = root / "dataset"
            report = prepare(coco, images, output)
            self.assertEqual(len(report["images"]), 2)
            self.assertEqual(
                report["excluded"],
                [
                    {
                        "image": rows[2]["file_name"],
                        "reason": "6 compartments, not seven",
                    }
                ],
            )
            self.assertFalse((output / "images/train" / rows[2]["file_name"]).exists())


class ModelContractTests(unittest.TestCase):
    def test_rectangle_checkpoint_cannot_silently_replace_compartment_masks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pills, compartments = root / "pills.pt", root / "compartments.pt"
            pills.touch()
            compartments.touch()
            pill_model = MagicMock(names={0: "acetaminophen", 1: "ibuprofen", 2: "iron"})
            rectangle_model = MagicMock(names={0: "compartment"}, task="detect")
            with patch("ultralytics.YOLO", side_effect=[pill_model, rectangle_model]):
                with self.assertRaisesRegex(ValueError, "segmentation model"):
                    OfficialVideoDetector(pills, compartments)


if __name__ == "__main__":
    unittest.main()
