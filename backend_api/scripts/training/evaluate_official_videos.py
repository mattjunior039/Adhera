"""Evaluate video predictions against separately provided human outcomes."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from backend_api.scripts.training.prepare_official_prototype import file_digest
from backend_api.services.official_pill_detection import PILL_CLASSES
from backend_api.services.official_video_detection import DAYS, OfficialVideoDetector


def exact_event_match(row: dict[str, object]) -> bool:
    expected = row["expected_event_type"]
    if row["event_type"] != f"CANDIDATE_{expected}":
        return False
    if row["day"] != row["expected_day"] or row["medication_class"] != row["expected_class"]:
        return False
    if expected == "TRANSFER":
        return (
            row["removed_count"] == 0
            and row["transferred_count"] == 1
            and row["destination_day"] == row["expected_destination_day"]
        )
    return expected == "SINGLE_REMOVAL" and row["removed_count"] == 1


def summarize(rows: list[dict[str, object]]) -> dict[str, object]:
    total = len(rows)
    predicted = [
        row
        for row in rows
        if row["event_type"]
        in {
            "CANDIDATE_SINGLE_REMOVAL",
            "CANDIDATE_TRANSFER",
        }
    ]
    correct = sum(exact_event_match(row) for row in predicted)
    removals = [row for row in rows if row["expected_event_type"] == "SINGLE_REMOVAL"]
    transfers = [row for row in rows if row["expected_event_type"] == "TRANSFER"]
    correct_removals = sum(exact_event_match(row) for row in removals)
    correct_transfers = sum(exact_event_match(row) for row in transfers)
    return {
        "videos": total,
        "exact_events_correct": correct,
        "exact_accuracy_percent": 100 * correct / total if total else None,
        "single_removal_videos": len(removals),
        "exact_single_removals_correct": correct_removals,
        "single_removal_success_percent": 100 * correct_removals / len(removals) if removals else None,
        "transfer_videos": len(transfers),
        "exact_transfers_correct": correct_transfers,
        "transfer_success_percent": 100 * correct_transfers / len(transfers) if transfers else None,
        "candidate_predictions": len(predicted),
        "coverage_percent": 100 * len(predicted) / total if total else None,
        "candidate_precision_percent": 100 * correct / len(predicted) if predicted else None,
        "incorrect_candidates": len(predicted) - correct,
        "abstentions_or_no_count_change": total - len(predicted),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", required=True, type=Path)
    parser.add_argument("--pill-checkpoint", required=True, type=Path)
    parser.add_argument("--compartment-checkpoint", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--comparison", choices=("strict", "target"), default="strict")
    parser.add_argument("--sample-fps", type=float, default=2.0)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a fresh output path")
    inputs = {}
    for name, path in (
        ("cases", args.cases),
        ("pill_checkpoint", args.pill_checkpoint),
        ("compartment_checkpoint", args.compartment_checkpoint),
    ):
        inputs[name] = {"path": str(path.resolve()), "sha256": file_digest(path)}
    cases = json.loads(args.cases.read_text(encoding="utf-8"))
    for case in cases:
        if case["expected_event_type"] not in {"SINGLE_REMOVAL", "TRANSFER"}:
            parser.error("Each case must explicitly specify SINGLE_REMOVAL or TRANSFER")
        if case["expected_day"] not in DAYS or case["expected_class"] not in PILL_CLASSES:
            parser.error("Each case must specify a known source day and pill class")
        if case["expected_event_type"] == "TRANSFER" and (
            case.get("expected_destination_day") not in DAYS
            or case["expected_destination_day"] == case["expected_day"]
        ):
            parser.error("Transfers require a distinct, known destination day")
    detector = OfficialVideoDetector(
        args.pill_checkpoint,
        args.compartment_checkpoint,
        args.device,
        comparison=args.comparison,
    )
    rows = []
    for case in cases:
        for assisted in (False, True):
            windows = None
            if assisted:
                before, after = case["windows"]
                b0, b1 = before
                a0, a1 = after
                windows = ((float(b0), float(b1)), (float(a0), float(a1)))
            # Expected day/class are not passed into the detector.
            report = dict(detector.analyze(Path(case["video"]), windows=windows, fps=args.sample_fps))
            report.update(
                clip=case["clip"],
                expected_day=case["expected_day"],
                expected_class=case["expected_class"],
                expected_event_type=case["expected_event_type"],
                expected_destination_day=case.get("expected_destination_day"),
                pill_training_overlap=case["pill_training_overlap"],
                compartment_training_overlap=case["compartment_training_overlap"],
            )
            rows.append(report)
            print(
                f"{case['clip']} {report['mode']}: {report['event_type']} "
                f"{report['day']} {report['medication_class']} "
                f"accepted={report['samples_accepted']}/{report['samples_total']}",
                flush=True,
            )
    summary = {
        mode: summarize([row for row in rows if row["mode"] == mode])
        for mode in ("automatic", "assisted_time_windows")
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(
            {
                "inputs": inputs,
                "device": args.device,
                "comparison": args.comparison,
                "sample_fps": args.sample_fps,
                "summary": summary,
                "limitations": [
                    "Four development clips, not an independent test set.",
                    "Pill model saw clips 1-3; clip 4 was used for model-selection validation.",
                    "Compartment model saw clip 1; clip 2 was used for model-selection validation.",
                    "Assisted mode uses manually reviewed timing; automatic mode does not.",
                    "Three confirmed removals and one confirmed compartment-to-compartment transfer.",
                    "No unchanged/hand-only negative videos in this evaluation.",
                    "Thresholds are provisional and uncalibrated. Every result requires human review.",
                ],
                "results": rows,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
