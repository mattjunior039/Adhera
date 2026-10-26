from __future__ import annotations

from pathlib import Path
from typing import Dict, Union

import cv2
import numpy as np
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend_api.models.inference_result import InferenceResult
from backend_api.models.photo_event import PhotoEvent

GRID_COLUMNS = 7
GRID_ROWS = 2
TOTAL_COMPARTMENTS = GRID_COLUMNS * GRID_ROWS

# Canonical top-down Adhera size after perspective rectification. Kept wide/short
# (7 columns x 2 rows) to match the physical AM/PM x weekday organizer layout.
CANONICAL_WIDTH = 1400
CANONICAL_HEIGHT = 400

# Whole-frame quality gate thresholds. Mirrors the conservative pattern used by
# ocr_service's label quality gate, tuned for a handheld Adhera scene rather than
# a printed label (less texture, more likely to have glare on the plastic lids).
_MIN_BLUR_SCORE = 15.0
_MIN_MEAN_INTENSITY = 35.0
_MAX_MEAN_INTENSITY = 225.0
_MAX_GLOBAL_GLARE_RATIO = 0.35

# Per-compartment occlusion threshold: a cell this saturated is unreadable, not empty.
_MAX_CELL_GLARE_RATIO = 0.40

# Only trust the Adhera-boundary contour if it covers a plausible fraction of the
# frame: too small to be the box, or so large it's probably background bleeding into
# the brightness mask, both fall back to treating the whole frame as the region.
_MIN_QUAD_AREA_RATIO = 0.15
_MAX_QUAD_AREA_RATIO = 0.85

# Empirical: the printed SUN..SAT weekday spine along one long edge of this organizer
# style isn't a compartment; excluding it keeps column boundaries aligned with the
# actual AM/PM slots instead of drifting by roughly one slot width.
_LABEL_MARGIN_FRACTION = 0.10


def _load_image(path: Union[str, Path]) -> np.ndarray:
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError(f"Unable to read image at {path}")
    return image


def _quality_gate(gray: np.ndarray) -> Dict[str, object]:
    """Reject frames that are too blurry, too dark/bright, or dominated by glare
    before any compartment logic runs on them, instead of silently misreading them."""
    blur_score = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    mean_intensity = float(np.mean(gray))
    glare_ratio = float(np.count_nonzero(gray > 245)) / float(gray.size)

    reasons = []
    if blur_score < _MIN_BLUR_SCORE:
        reasons.append("image_too_blurry")
    if mean_intensity < _MIN_MEAN_INTENSITY:
        reasons.append("image_too_dark")
    if mean_intensity > _MAX_MEAN_INTENSITY:
        reasons.append("image_too_bright")
    if glare_ratio > _MAX_GLOBAL_GLARE_RATIO:
        reasons.append("excessive_glare")

    return {
        "passed": not reasons,
        "blur_score": round(blur_score, 2),
        "mean_intensity": round(mean_intensity, 2),
        "glare_ratio": round(glare_ratio, 4),
        "reason": ", ".join(reasons) if reasons else None,
    }


def _order_quad_corners(points: np.ndarray) -> np.ndarray:
    """Order 4 points as top-left, top-right, bottom-right, bottom-left.
    Ensures the longest edge is mapped horizontally so vertical videos don't
    squash the 7x2 grid sideways."""
    rect = np.zeros((4, 2), dtype=np.float32)
    total = points.sum(axis=1)
    diff = np.diff(points, axis=1).reshape(-1)

    tl = points[np.argmin(total)]
    br = points[np.argmax(total)]
    tr = points[np.argmin(diff)]
    bl = points[np.argmax(diff)]

    width_top = np.linalg.norm(tr - tl)
    height_left = np.linalg.norm(bl - tl)

    if height_left > width_top:
        # The Adhera organizer is rotated vertically in the frame.
        # Rotate the corner mapping by 90 degrees so it maps to a wide landscape image.
        rect[0] = bl
        rect[1] = tl
        rect[2] = tr
        rect[3] = br
    else:
        rect[0] = tl
        rect[1] = tr
        rect[2] = br
        rect[3] = bl

    return rect


def _detect_adhera_quad(image: np.ndarray) -> np.ndarray:
    """Locate the Adhera boundary and return its 4 corners (tl, tr, br, bl).

    Falls back to the full frame if no confident quadrilateral can be found, so the
    rest of the pipeline degrades gracefully instead of failing outright (same
    fallback philosophy as ocr_service's label-region detection).
    """
    height, width = image.shape[:2]
    fallback = np.array(
        [[0, 0], [width - 1, 0], [width - 1, height - 1], [0, height - 1]],
        dtype=np.float32,
    )

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    blurred = cv2.GaussianBlur(gray, (7, 7), 0)
    # The Adhera organizer's white/pastel plastic is markedly brighter than a wood-grain
    # background; brightness segmentation is far more reliable on real handheld
    # footage than Canny edges, which fragment across busy wood-grain textures.
    _, mask = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((25, 25), np.uint8), iterations=2)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((15, 15), np.uint8))

    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return fallback

    largest = max(contours, key=cv2.contourArea)
    rect = cv2.minAreaRect(largest)
    box = cv2.boxPoints(rect)
    # Gate on the rotated bounding box actually used for warping, not the raw contour
    # area — an irregular/occluded contour can have a modest area but a minAreaRect
    # that balloons to nearly the whole frame, silently defeating this safety check.
    box_area_ratio = (rect[1][0] * rect[1][1]) / float(width * height)
    if box_area_ratio < _MIN_QUAD_AREA_RATIO or box_area_ratio > _MAX_QUAD_AREA_RATIO:
        return fallback

    return _order_quad_corners(np.array(box, dtype=np.float32))


def _rectify_adhera_color(image: np.ndarray) -> np.ndarray:
    """Warp the detected Adhera region to a canonical top-down color view so
    compartment cells line up regardless of phone angle/rotation."""
    quad = _detect_adhera_quad(image)
    destination = np.array(
        [
            [0, 0],
            [CANONICAL_WIDTH - 1, 0],
            [CANONICAL_WIDTH - 1, CANONICAL_HEIGHT - 1],
            [0, CANONICAL_HEIGHT - 1],
        ],
        dtype=np.float32,
    )
    matrix = cv2.getPerspectiveTransform(quad, destination)
    return cv2.warpPerspective(image, matrix, (CANONICAL_WIDTH, CANONICAL_HEIGHT))


def _rectify_adhera(image: np.ndarray) -> np.ndarray:
    """Grayscale variant of `_rectify_adhera_color`, used by the photo diff pipeline."""
    warped = _rectify_adhera_color(image)
    return cv2.cvtColor(warped, cv2.COLOR_BGR2GRAY) if warped.ndim == 3 else warped


def _segment_compartments(image: np.ndarray) -> list[np.ndarray]:
    """Slice a canonical image (grayscale or color) into the 14 compartment cells,
    skipping the printed label spine at the start of the row (see `_LABEL_MARGIN_FRACTION`)."""
    height, width = image.shape[:2]
    margin = int(width * _LABEL_MARGIN_FRACTION)
    usable_width = width - margin
    cell_width = usable_width // GRID_COLUMNS
    cell_height = height // GRID_ROWS
    cells: list[np.ndarray] = []

    for row in range(GRID_ROWS):
        for col in range(GRID_COLUMNS):
            x_start = margin + col * cell_width
            y_start = row * cell_height
            x_end = x_start + cell_width if col < GRID_COLUMNS - 1 else width
            y_end = y_start + cell_height if row < GRID_ROWS - 1 else height
            cells.append(image[y_start:y_end, x_start:x_end])

    return cells


def _cell_glare_ratio(cell: np.ndarray) -> float:
    return float(np.count_nonzero(cell > 245)) / float(max(1, cell.size))


def detect_compartment_changes(
    baseline_path: Union[str, Path], current_path: Union[str, Path]
) -> list[Dict[str, object]]:
    baseline_raw = _load_image(baseline_path)
    current_raw = _load_image(current_path)

    baseline_quality = _quality_gate(cv2.cvtColor(baseline_raw, cv2.COLOR_BGR2GRAY))
    current_quality = _quality_gate(cv2.cvtColor(current_raw, cv2.COLOR_BGR2GRAY))
    if not baseline_quality["passed"] or not current_quality["passed"]:
        bad = baseline_quality if not baseline_quality["passed"] else current_quality
        raise ValueError(f"Photo failed quality gate ({bad['reason']}); please recapture.")

    # Perspective-correct both frames onto the same canonical grid before diffing,
    # so a rotated/angled phone shot still maps to the right compartment index.
    baseline = _rectify_adhera(baseline_raw)
    current = _rectify_adhera(current_raw)

    diff = cv2.absdiff(baseline, current)
    _, thresholded = cv2.threshold(diff, 25, 255, cv2.THRESH_BINARY)
    baseline_cells = _segment_compartments(baseline)
    current_cells = _segment_compartments(current)
    diff_cells = _segment_compartments(thresholded)

    global_quality_score = round(
        min(1.0 - baseline_quality["glare_ratio"], 1.0 - current_quality["glare_ratio"]), 4
    )

    results: list[dict] = []
    for index in range(TOTAL_COMPARTMENTS):
        baseline_cell = baseline_cells[index]
        current_cell = current_cells[index]
        diff_cell = diff_cells[index]

        cell_glare = max(_cell_glare_ratio(baseline_cell), _cell_glare_ratio(current_cell))
        if cell_glare > _MAX_CELL_GLARE_RATIO:
            # Glare/occlusion must never be reported as "empty" or "unchanged".
            results.append(
                {
                    "compartment_index": index,
                    "is_changed": False,
                    "confidence": 0.0,
                    "state": "occluded",
                    "quality_score": round(1.0 - cell_glare, 4),
                }
            )
            continue

        baseline_mean = float(np.mean(baseline_cell))
        current_mean = float(np.mean(current_cell))
        diff_pixels = float(np.count_nonzero(diff_cell)) / max(1.0, diff_cell.size)

        changed = diff_pixels > 0.05 or abs(baseline_mean - current_mean) > 20
        confidence = min(0.99, max(0.10, abs(baseline_mean - current_mean) / 80.0 + diff_pixels * 1.5))
        if not changed:
            confidence = max(0.55, min(0.99, confidence))

        results.append(
            {
                "compartment_index": index,
                "is_changed": bool(changed),
                "confidence": round(float(confidence), 4),
                "state": "changed" if changed else "unchanged",
                "quality_score": global_quality_score,
            }
        )

    return results


async def analyze_photo_event(
    db: AsyncSession, photo_event_id: int, baseline_event_id: int
) -> list[InferenceResult]:
    photo_event = await db.get(PhotoEvent, photo_event_id)
    baseline_event = await db.get(PhotoEvent, baseline_event_id)

    if photo_event is None:
        raise ValueError(f"Photo event {photo_event_id} was not found")
    if baseline_event is None:
        raise ValueError(f"Baseline photo event {baseline_event_id} was not found")

    current_path = photo_event.photo_path
    baseline_path = baseline_event.photo_path

    if not current_path or not baseline_path:
        raise ValueError("Both baseline and current photo paths are required for analysis")

    results = detect_compartment_changes(baseline_path, current_path)

    existing = await db.execute(
        select(InferenceResult)
        .where(
            InferenceResult.photo_event_id == photo_event_id,
            InferenceResult.baseline_event_id == baseline_event_id,
        )
        .order_by(InferenceResult.compartment_index.asc())
    )
    existing_results = list(existing.scalars().all())
    if existing_results:
        return existing_results

    persisted: list[InferenceResult] = []
    for item in results:
        saved = InferenceResult(
            photo_event_id=photo_event_id,
            baseline_event_id=baseline_event_id,
            compartment_index=item["compartment_index"],
            is_changed=item["is_changed"],
            confidence=item["confidence"],
            state=item["state"],
            quality_score=item["quality_score"],
        )
        db.add(saved)
        persisted.append(saved)

    await db.commit()
    for row in persisted:
        await db.refresh(row)
    return persisted
