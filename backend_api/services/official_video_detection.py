"""Experimental seven-compartment video counting; independent of expected outcomes."""

from __future__ import annotations

import math
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Literal, NotRequired, Required, Sequence, TypedDict

import cv2
import numpy as np

from backend_api.services.official_pill_detection import PILL_CLASSES, load_detector

DAYS = ("SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT")


class FrameInspection(TypedDict, total=False):
    accepted: Required[bool]
    counts: list[int]
    reason: str
    compartments_detected: int
    compartments: list[list[float]]
    compartment_polygons: list[list[list[float]]]
    pills: list[dict[str, object]]


class FrameSample(FrameInspection):
    seconds: float


class CompartmentComparison(TypedDict):
    event_type: str
    medication_class: str | None
    day: str | None
    period: str
    removed_count: int | None
    requires_review: bool
    destination_day: str | None
    transferred_count: int | None
    before_agreement: float
    after_agreement: float
    before_counts: list[int] | None
    after_counts: list[int] | None
    reason: str
    evidence_scope: NotRequired[str]
    class_evidence: NotRequired[dict[str, CompartmentComparison]]


class VideoReport(CompartmentComparison):
    video: str
    mode: str
    sample_fps: float
    duration_seconds: float
    comparison: str
    samples_total: int
    samples_accepted: int
    before_seconds: list[float]
    after_seconds: list[float]
    rejections: dict[str, int]
    samples: list[FrameSample]


class VideoVerificationResult(VideoReport):
    compartment_index: int | None
    assumed_label: str | None
    am_row: int | None
    period_confident: bool
    orientation_calibrated: bool
    pre_count: int | None
    post_count: int | None
    frames_sampled: int
    frames_accepted: int
    confidence: float
    model_provenance: dict[str, str]
    prototype: str


@dataclass(frozen=True)
class Box:
    class_id: int
    confidence: float
    xyxy: tuple[float, float, float, float]
    polygon: tuple[tuple[float, float], ...] = ()

    @property
    def center(self) -> tuple[float, float]:
        x1, y1, x2, y2 = self.xyxy
        return (x1 + x2) / 2, (y1 + y2) / 2


def order_compartments(boxes: Sequence[Box]) -> list[Box] | None:
    if len(boxes) != 7:
        return None
    ordered = sorted(boxes, key=lambda box: box.center[0])
    if any(not all(math.isfinite(v) for v in box.xyxy) for box in ordered):
        return None
    widths = [box.xyxy[2] - box.xyxy[0] for box in ordered]
    heights = [box.xyxy[3] - box.xyxy[1] for box in ordered]
    if min(widths + heights) <= 0:
        return None
    for first, second in zip(ordered, ordered[1:]):
        gap = second.center[0] - first.center[0]
        if gap < min(first.xyxy[2] - first.xyxy[0], second.xyxy[2] - second.xyxy[0]) * 0.35:
            return None
        if min(first.xyxy[3], second.xyxy[3]) <= max(first.xyxy[1], second.xyxy[1]):
            return None
    return ordered


def compartment_counts(
    compartments: Sequence[Box],
    pills: Sequence[Box],
) -> tuple[int, ...] | None:
    ordered = order_compartments(compartments)
    if ordered is None:
        return None
    counts = [0] * (7 * len(PILL_CLASSES))
    for pill in pills:
        if pill.class_id not in range(len(PILL_CLASSES)):
            raise ValueError("Unknown pill class")
        x, y = pill.center
        matches = []
        for i, cell in enumerate(ordered):
            if cell.polygon:
                inside = cv2.pointPolygonTest(np.asarray(cell.polygon, dtype=np.float32), (x, y), False) >= 0
            else:
                inside = cell.xyxy[0] <= x <= cell.xyxy[2] and cell.xyxy[1] <= y <= cell.xyxy[3]
            if inside:
                matches.append(i)
        if len(matches) != 1:
            return None
        counts[matches[0] * len(PILL_CLASSES) + pill.class_id] += 1
    return tuple(counts)


def phase_consensus(
    frames: Sequence[Sequence[int]],
    min_frames: int = 3,
    agreement: float = 0.75,
) -> tuple[tuple[int, ...] | None, float]:
    if min_frames < 2 or not 0.5 < agreement <= 1:
        raise ValueError("Require at least two frames and a strict-majority agreement threshold")
    for frame in frames:
        if len(frame) != 21 or any(type(n) is not int or n < 0 for n in frame):
            raise ValueError("Each frame must contain 21 nonnegative integer counts")
    if len(frames) < min_frames:
        return None, 0.0
    # Joint-vector agreement avoids constructing a combination never observed in a frame.
    vector, support = Counter(tuple(frame) for frame in frames).most_common(1)[0]
    ratio = support / len(frames)
    return (vector if support >= min_frames and ratio >= agreement else None), ratio


def compare_compartments(
    before: Sequence[Sequence[int]],
    after: Sequence[Sequence[int]],
) -> CompartmentComparison:
    pre, pre_support = phase_consensus(before)
    post, post_support = phase_consensus(after)
    report: CompartmentComparison = {
        "event_type": "INCONCLUSIVE",
        "medication_class": None,
        "day": None,
        "period": "PM",
        "removed_count": None,
        "requires_review": True,
        "destination_day": None,
        "transferred_count": None,
        "before_agreement": pre_support,
        "after_agreement": post_support,
        "before_counts": list(pre) if pre is not None else None,
        "after_counts": list(post) if post is not None else None,
        "reason": "Insufficient consistent seven-compartment views in one or both phases.",
    }
    if pre is None or post is None:
        return report
    delta = [a - b for a, b in zip(pre, post)]
    if not any(delta):
        report.update(event_type="NO_COUNT_CHANGE", reason="Stable detected counts are unchanged.")
    elif delta.count(1) == 1 and delta.count(0) == 20:
        index = delta.index(1)
        report.update(
            event_type="CANDIDATE_SINGLE_REMOVAL",
            day=DAYS[index // 3],
            medication_class=PILL_CLASSES[index % 3],
            removed_count=1,
            reason="Exactly one pill-class count decreased by one in one compartment.",
        )
    elif delta.count(1) == 1 and delta.count(-1) == 1 and delta.count(0) == 19:
        origin, destination = delta.index(1), delta.index(-1)
        if origin % 3 == destination % 3:
            report.update(
                event_type="CANDIDATE_TRANSFER",
                day=DAYS[origin // 3],
                destination_day=DAYS[destination // 3],
                medication_class=PILL_CLASSES[origin % 3],
                removed_count=0,
                transferred_count=1,
                reason="One pill of the same class moved between compartments; not a net removal.",
            )
        else:
            report["reason"] = "Different classes decreased and increased; not a verified transfer."
    else:
        report["reason"] = "Multiple count changes or additions; not a unique one-pill extraction."
    return report


def _prediction_boxes(model, frame: np.ndarray, confidence: float, device: str) -> list[Box]:
    result = model.predict(
        frame,
        conf=confidence,
        imgsz=640,
        device=device,
        verbose=False,
    )[0]
    if result.boxes is None:
        return []
    polygons = result.masks.xy if result.masks is not None else None
    return [
        Box(
            int(box.cls.item()),
            float(box.conf.item()),
            tuple(box.xyxy[0].tolist()),
            tuple(tuple(point) for point in polygons[index].tolist()) if polygons is not None else (),
        )
        for index, box in enumerate(result.boxes)
    ]


def compare_target_medications(
    before: Sequence[Sequence[int]],
    after: Sequence[Sequence[int]],
) -> CompartmentComparison:
    """Compare observed seven-day vectors per target class, not synthetic cell majorities."""
    report = compare_compartments(before, after)
    diagnostics = {}
    candidates = []
    conflicting_changes = False
    for class_id, name in enumerate(PILL_CLASSES[:2]):
        phases = [
            [[count if index % 3 == class_id else 0 for index, count in enumerate(frame)] for frame in phase]
            for phase in (before, after)
        ]
        evidence = compare_compartments(*phases)
        diagnostics[name] = evidence
        if evidence["event_type"] in {"CANDIDATE_SINGLE_REMOVAL", "CANDIDATE_TRANSFER"}:
            candidates.append(evidence)
        elif evidence["before_counts"] is not None and evidence["after_counts"] is not None:
            conflicting_changes |= evidence["before_counts"] != evidence["after_counts"]
    if len(candidates) == 1 and not conflicting_changes:
        report = candidates[0].copy()
        report["reason"] = (
            "Review-only target-class evidence: "
            + str(report["reason"])
            + " Other classes may be unstable; this is not whole-box verification."
        )
    else:
        report = compare_compartments([], [])
        if len(candidates) > 1 or conflicting_changes:
            report["reason"] = "Competing target-medication changes; no unique event."
        elif all(e["event_type"] == "NO_COUNT_CHANGE" for e in diagnostics.values()):
            report.update(
                event_type="NO_COUNT_CHANGE", reason="Stable target counts unchanged; iron not verified."
            )
    report.update(
        evidence_scope="acetaminophen_ibuprofen_only",
        class_evidence=diagnostics,
        requires_review=True,
    )
    return report


class OfficialVideoDetector:
    def __init__(
        self,
        pill_checkpoint: Path,
        compartment_checkpoint: Path,
        device: str = "cpu",
        comparison: Literal["strict", "target"] = "strict",
    ):
        from ultralytics import YOLO

        if comparison not in {"strict", "target"}:
            raise ValueError("Comparison must be strict or target")
        self.comparison = comparison
        self.pill_model = load_detector(pill_checkpoint)
        if not compartment_checkpoint.is_file():
            raise ValueError(f"Missing compartment model: {compartment_checkpoint}")
        self.compartment_model = YOLO(str(compartment_checkpoint))
        if self.compartment_model.names != {0: "compartment"} or self.compartment_model.task != "segment":
            raise ValueError("Expected a one-class compartment segmentation model")
        self.device = device

    def inspect_frame(self, frame: np.ndarray) -> FrameInspection:
        compartments = _prediction_boxes(self.compartment_model, frame, 0.35, self.device)
        ordered = order_compartments(compartments)
        if ordered is None:
            return {
                "accepted": False,
                "reason": "incomplete_or_ambiguous_layout",
                "compartments_detected": len(compartments),
            }
        for box in ordered:
            x1, y1, x2, y2 = map(int, box.xyxy)
            cell = frame[max(0, y1) : y2, max(0, x1) : x2]
            if cell.size == 0:
                return {"accepted": False, "reason": "empty_crop"}
            hsv = cv2.cvtColor(cell, cv2.COLOR_BGR2HSV)
            skin = cv2.inRange(hsv, np.array([0, 30, 60]), np.array([20, 150, 255]))
            if np.count_nonzero(skin) / skin.size > 0.20:
                return {"accepted": False, "reason": "possible_hand_occlusion"}
        pills = _prediction_boxes(self.pill_model, frame, 0.5, self.device)
        counts = compartment_counts(ordered, pills)
        if counts is None:
            return {"accepted": False, "reason": "ambiguous_pill_assignment"}
        return {
            "accepted": True,
            "counts": list(counts),
            "compartments": [list(box.xyxy) for box in ordered],
            "compartment_polygons": [[list(point) for point in box.polygon] for box in ordered],
            "pills": [
                {"class": PILL_CLASSES[box.class_id], "confidence": box.confidence, "xyxy": list(box.xyxy)}
                for box in pills
            ],
        }

    def analyze(
        self,
        video: Path,
        windows: tuple[tuple[float, float], tuple[float, float]] | None = None,
        fps: float = 2.0,
        max_duration_seconds: float | None = None,
    ) -> VideoReport:
        if not math.isfinite(fps) or not 0 < fps <= 10:
            raise ValueError("Sample FPS must be finite and in (0, 10]")
        if max_duration_seconds is not None and (
            not math.isfinite(max_duration_seconds) or max_duration_seconds <= 0
        ):
            raise ValueError("Maximum duration must be positive and finite")
        cap = cv2.VideoCapture(str(video))
        if not cap.isOpened():
            cap.release()
            raise ValueError(f"Unable to open {video}")
        try:
            rate = cap.get(cv2.CAP_PROP_FPS)
            total = cap.get(cv2.CAP_PROP_FRAME_COUNT)
            if not math.isfinite(rate) or not math.isfinite(total) or rate <= 0 or total <= 0:
                raise ValueError("Video has invalid frame timing")
            duration = total / rate
            if not math.isfinite(duration) or duration <= 0:
                raise ValueError("Video has invalid duration")
            if max_duration_seconds is not None and duration > max_duration_seconds:
                raise ValueError(f"Video exceeds the {max_duration_seconds:g}-second limit")
            if windows is not None:
                (b0, b1), (a0, a1) = windows
                if not all(math.isfinite(v) for v in (b0, b1, a0, a1)) or not (
                    0 <= b0 < b1 < a0 < a1 < duration
                ):
                    raise ValueError("Phase windows must be ordered, disjoint and inside the video")
                times = sorted(
                    set(
                        start + index / fps
                        for start, end in windows
                        for index in range(int((end - start) * fps) + 1)
                    )
                )
            else:
                times = [i / fps for i in range(math.ceil(duration * fps))]
            samples: list[FrameSample] = []
            for seconds in times:
                cap.set(cv2.CAP_PROP_POS_MSEC, seconds * 1000)
                ok, frame = cap.read()
                if not ok or frame is None:
                    samples.append({"seconds": seconds, "accepted": False, "reason": "decode_failed"})
                    continue
                inspection = self.inspect_frame(frame)
                if inspection["accepted"] and "counts" not in inspection:
                    raise RuntimeError("Accepted frame has no count evidence")
                if not inspection["accepted"] and "reason" not in inspection:
                    raise RuntimeError("Rejected frame has no rejection reason")
                samples.append({**inspection, "seconds": seconds})
        finally:
            cap.release()
        accepted = [sample for sample in samples if sample["accepted"]]
        if windows is None:
            # Fixed first/last readable windows; never search for a change matching expected truth.
            pre = [s for s in accepted if s["seconds"] <= accepted[0]["seconds"] + 1.5] if accepted else []
            post = [s for s in accepted if s["seconds"] >= accepted[-1]["seconds"] - 1.5] if accepted else []
        else:
            pre = [s for s in accepted if windows[0][0] <= s["seconds"] <= windows[0][1]]
            post = [s for s in accepted if windows[1][0] <= s["seconds"] <= windows[1][1]]
        if pre and post and pre[-1]["seconds"] >= post[0]["seconds"]:
            report = compare_compartments([], [])
            report["reason"] = "Readable before/after windows overlap."
        else:
            compare = compare_target_medications if self.comparison == "target" else compare_compartments
            report = compare(
                [s["counts"] for s in pre if "counts" in s],
                [s["counts"] for s in post if "counts" in s],
            )
        if self.comparison == "target":
            report["evidence_scope"] = "acetaminophen_ibuprofen_only"
        return {
            **report,
            "video": str(video.resolve()),
            "mode": "assisted_time_windows" if windows is not None else "automatic",
            "sample_fps": fps,
            "duration_seconds": duration,
            "comparison": self.comparison,
            "samples_total": len(samples),
            "samples_accepted": len(accepted),
            "before_seconds": [s["seconds"] for s in pre],
            "after_seconds": [s["seconds"] for s in post],
            "rejections": dict(Counter(s["reason"] for s in samples if not s["accepted"] and "reason" in s)),
            "samples": samples,
        }
