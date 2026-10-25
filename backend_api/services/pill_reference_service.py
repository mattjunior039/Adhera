from __future__ import annotations

from functools import lru_cache
from io import BytesIO
from math import sqrt
from pathlib import Path
from typing import Dict, List

from PIL import Image, UnidentifiedImageError

from backend_api.services.pill_identity import (
    PillEmbeddingUnavailable,
    generate_pill_signature,
)

REFERENCE_DIR = Path(__file__).resolve().parents[1] / "datasets" / "pill_references"


def match_pill_signature(
    signature: List[float],
    references: Dict[str, List[List[float]]],
) -> dict[str, object]:
    """Return the nearest labeled sample; this is a candidate, not a diagnosis."""
    query_norm = sqrt(sum(value * value for value in signature))
    if query_norm == 0:
        raise ValueError("The uploaded image did not produce a usable pill signature")

    similarities: dict[str, float] = {}
    for medication_name, examples in references.items():
        scores = []
        for example in examples:
            if len(example) != len(signature):
                continue
            example_norm = sqrt(sum(value * value for value in example))
            if example_norm == 0:
                continue
            dot = sum(left * right for left, right in zip(signature, example))
            scores.append(dot / (query_norm * example_norm))
        if scores:
            similarities[medication_name] = max(scores)

    if not similarities:
        raise PillEmbeddingUnavailable("No usable labeled pill reference images were found")

    ranked = sorted(similarities.items(), key=lambda item: item[1], reverse=True)
    return {
        "medication_name": ranked[0][0],
        "similarity": round(ranked[0][1], 4),
        "runner_up_similarity": round(ranked[1][1], 4) if len(ranked) > 1 else None,
        "requires_review": True,
    }


@lru_cache(maxsize=1)
def _reference_signatures() -> Dict[str, List[List[float]]]:
    references: Dict[str, List[List[float]]] = {}
    for medication_dir in sorted(REFERENCE_DIR.iterdir()):
        if not medication_dir.is_dir():
            continue
        signatures = []
        for image_path in sorted(medication_dir.glob("*.jpg")):
            with Image.open(image_path) as image:
                signatures.append(generate_pill_signature(image.convert("RGB")))
        if signatures:
            references[medication_dir.name.replace("_", " ").title()] = signatures
    return references


def identify_reference_image(image_bytes: bytes) -> dict[str, object]:
    try:
        with Image.open(BytesIO(image_bytes)) as image:
            signature = generate_pill_signature(image.convert("RGB"))
    except (UnidentifiedImageError, OSError) as exc:
        raise ValueError("The uploaded file is not a readable image") from exc
    return match_pill_signature(signature, _reference_signatures())
