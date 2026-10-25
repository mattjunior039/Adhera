"""Review-only video adapter for the official Sunday-to-Saturday blue PM row."""

from __future__ import annotations

import hashlib
import os
import threading
from functools import lru_cache
from pathlib import Path
from typing import TYPE_CHECKING

from backend_api.services.official_pill_detection import PILL_CLASSES

if TYPE_CHECKING:
    from backend_api.services.official_video_detection import VideoVerificationResult

_MODEL_ROOT = Path(__file__).resolve().parents[1] / "runs" / "official_blue_pm" / "corrected_batch_01"
_inference_lock = threading.Lock()


class VideoModelUnavailable(RuntimeError):
    pass


class VideoAnalysisBusy(RuntimeError):
    pass


@lru_cache(maxsize=1)
def _load_models(pills: str, compartments: str, device: str):
    try:
        from backend_api.services.official_video_detection import OfficialVideoDetector

        paths = (Path(pills), Path(compartments))
        if any(not path.is_file() for path in paths):
            raise VideoModelUnavailable(
                "Official video weights are missing. Configure OFFICIAL_PILL_CHECKPOINT "
                "and OFFICIAL_COMPARTMENT_CHECKPOINT."
            )
        detector = OfficialVideoDetector(*paths, device=device, comparison="target")
        hashes = {
            name: hashlib.sha256(path.read_bytes()).hexdigest()
            for name, path in zip(("pills_sha256", "compartments_sha256"), paths)
        }
        return detector, hashes
    except (ImportError, OSError, ValueError, RuntimeError) as exc:
        raise VideoModelUnavailable(f"Official video models unavailable: {exc}") from exc


def analyze_dose_removal_video(
    video_path: str | Path,
    *,
    windows: tuple[tuple[float, float], tuple[float, float]] | None = None,
) -> VideoVerificationResult:
    if not _inference_lock.acquire(blocking=False):
        raise VideoAnalysisBusy("Video analysis is busy; retry after the current request finishes.")
    try:
        from backend_api.services.official_video_detection import DAYS

        detector, hashes = _load_models(
            os.environ.get("OFFICIAL_PILL_CHECKPOINT", str(_MODEL_ROOT / "pills_model/weights/best.pt")),
            os.environ.get(
                "OFFICIAL_COMPARTMENT_CHECKPOINT", str(_MODEL_ROOT / "compartments_model/weights/best.pt")
            ),
            os.environ.get("OFFICIAL_VIDEO_DEVICE", "cpu"),
        )
        report = detector.analyze(Path(video_path), windows=windows, fps=4, max_duration_seconds=120)
        day = report["day"]
        medication = report["medication_class"]
        column = DAYS.index(day) if day is not None else None
        counts = []
        for phase in ("before_counts", "after_counts"):
            vector = report[phase]
            if column is not None and medication is not None and vector is not None:
                counts.append(vector[column * 3 + PILL_CLASSES.index(medication)])
            else:
                counts.append(None)
        return {
            **report,
            "compartment_index": 7 + column if column is not None else None,
            "assumed_label": f"{day}_PM" if day else None,
            "am_row": None,
            "period_confident": True,
            "orientation_calibrated": False,
            "pre_count": counts[0],
            "post_count": counts[1],
            "frames_sampled": report["samples_total"],
            "frames_accepted": report["samples_accepted"],
            "confidence": min(report["before_agreement"], report["after_agreement"])
            if column is not None
            else 0.0,
            "requires_review": True,
            "model_provenance": hashes,
            "prototype": "official_blue_pm",
        }
    finally:
        _inference_lock.release()
