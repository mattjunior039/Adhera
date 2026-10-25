"""Conservative, review-only count comparison for the official blue-PM prototype."""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, TypedDict

PILL_CLASSES = ("acetaminophen", "ibuprofen", "iron")


def load_detector(checkpoint: Path):
    if not checkpoint.is_file():
        raise ValueError(f"Checkpoint not found: {checkpoint}")
    from ultralytics import YOLO

    model = YOLO(str(checkpoint))
    if tuple(model.names[index] for index in range(len(model.names))) != PILL_CLASSES:
        raise ValueError(f"Checkpoint classes must be exactly {PILL_CLASSES}; got {model.names}")
    return model


class Comparison(TypedDict):
    event_type: str
    medication_class: str | None
    removed_count: int | None
    before_counts: dict[str, int] | None
    after_counts: dict[str, int] | None
    requires_review: bool
    reason: str


def stable_counts(frames: Sequence[Sequence[int]]) -> tuple[int, ...] | None:
    for frame in frames:
        if len(frame) != len(PILL_CLASSES) or any(type(n) is not int or n < 0 for n in frame):
            raise ValueError("Counts must be three nonnegative integers in PILL_CLASSES order")
    if len(frames) < 2:
        return None
    first = tuple(frames[0])
    return first if all(tuple(frame) == first for frame in frames[1:]) else None


def compare_counts(
    before: Sequence[Sequence[int]],
    after: Sequence[Sequence[int]],
) -> Comparison:
    pre, post = stable_counts(before), stable_counts(after)
    result: Comparison = {
        "event_type": "INCONCLUSIVE",
        "medication_class": None,
        "removed_count": None,
        "before_counts": dict(zip(PILL_CLASSES, pre)) if pre is not None else None,
        "after_counts": dict(zip(PILL_CLASSES, post)) if post is not None else None,
        "requires_review": True,
        "reason": "Need at least two agreeing, independently selected clear views in each phase.",
    }
    if pre is None or post is None:
        return result
    delta = tuple(a - b for a, b in zip(pre, post))
    if all(change == 0 for change in delta):
        result["event_type"] = "NO_COUNT_CHANGE"
        result["reason"] = "Stable detected counts are unchanged; this does not prove no removal."
    elif delta.count(1) == 1 and delta.count(0) == len(PILL_CLASSES) - 1:
        result["event_type"] = "CANDIDATE_SINGLE_REMOVAL"
        result["medication_class"] = PILL_CLASSES[delta.index(1)]
        result["removed_count"] = 1
        result["reason"] = "One detected class fell by one; human review is mandatory for this pilot."
    else:
        result["reason"] = "Counts show additions, multiple removals, or conflicting class changes."
    return result
