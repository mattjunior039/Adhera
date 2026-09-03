from __future__ import annotations

from pathlib import Path
from typing import Dict, Union

import cv2
import numpy as np

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

try:
    from backend_api.models.inference_result import InferenceResult
    from backend_api.models.photo_event import PhotoEvent
except ImportError:  # pragma: no cover - script execution fallback
    from models.inference_result import InferenceResult
    from models.photo_event import PhotoEvent

GRID_COLUMNS = 7
GRID_ROWS = 2
TOTAL_COMPARTMENTS = GRID_COLUMNS * GRID_ROWS


def _load_image(path: Union[str, Path]) -> np.ndarray:
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError(f"Unable to read image at {path}")
    return image


def _prepare_image(image: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    resized = cv2.resize(gray, (700, 200), interpolation=cv2.INTER_AREA)
    return resized


def _segment_compartments(image: np.ndarray) -> list[np.ndarray]:
    height, width = image.shape
    cell_width = width // GRID_COLUMNS
    cell_height = height // GRID_ROWS
    cells: list[np.ndarray] = []

    for row in range(GRID_ROWS):
        for col in range(GRID_COLUMNS):
            x_start = col * cell_width
            y_start = row * cell_height
            x_end = x_start + cell_width if col < GRID_COLUMNS - 1 else width
            y_end = y_start + cell_height if row < GRID_ROWS - 1 else height
            cells.append(image[y_start:y_end, x_start:x_end])

    return cells


def detect_compartment_changes(baseline_path: Union[str, Path], current_path: Union[str, Path]) -> list[Dict[str, object]]:
    baseline = _prepare_image(_load_image(baseline_path))
    current = _prepare_image(_load_image(current_path))

    if baseline.shape != current.shape:
        height = min(baseline.shape[0], current.shape[0])
        width = min(baseline.shape[1], current.shape[1])
        baseline = cv2.resize(baseline, (width, height))
        current = cv2.resize(current, (width, height))

    diff = cv2.absdiff(baseline, current)
    _, thresholded = cv2.threshold(diff, 25, 255, cv2.THRESH_BINARY)
    baseline_cells = _segment_compartments(baseline)
    current_cells = _segment_compartments(current)
    diff_cells = _segment_compartments(thresholded)

    results: list[dict] = []
    for index in range(TOTAL_COMPARTMENTS):
        baseline_cell = baseline_cells[index]
        current_cell = current_cells[index]
        diff_cell = diff_cells[index]

        baseline_mean = float(np.mean(baseline_cell))
        current_mean = float(np.mean(current_cell))
        diff_pixels = float(np.count_nonzero(diff_cell)) / max(1.0, diff_cell.size)

        changed = diff_pixels > 0.05 or abs(baseline_mean - current_mean) > 20
        confidence = min(0.99, max(0.10, abs(baseline_mean - current_mean) / 80.0 + diff_pixels * 1.5))
        if not changed:
            confidence = max(0.55, min(0.99, confidence))

        results.append({
            "compartment_index": index,
            "is_changed": bool(changed),
            "confidence": round(float(confidence), 4),
        })

    return results


async def analyze_photo_event(db: AsyncSession, photo_event_id: int, baseline_event_id: int) -> list[InferenceResult]:
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
        select(InferenceResult).where(
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
        )
        db.add(saved)
        persisted.append(saved)

    await db.commit()
    for row in persisted:
        await db.refresh(row)
    return persisted
