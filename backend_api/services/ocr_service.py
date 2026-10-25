"""Local prescription label scanning.

Pipeline:
- quality gate (blur, exposure, contrast, skew) before parsing
- automatic label-region flattening and crop for the review preview
- field extraction from the text the phone recognized on-device
- drug-name normalization against NIH RxNorm (see drug_dictionary.py)

Label images are processed on the Adhera backend and are never sent to an
external service. Only the candidate drug name is looked up in RxNorm.
"""

from __future__ import annotations

import base64
import re
from pathlib import Path
from typing import Dict, List, Optional, Union

import cv2
import numpy as np

PILImage = None
PILImageOps = None
try:
    from PIL import Image as PILImage  # type: ignore[import-not-found]
    from PIL import ImageOps as PILImageOps  # type: ignore[import-not-found]
except ImportError:
    pass


def _load_image(image_path: Union[str, Path]) -> np.ndarray:
    img = cv2.imread(str(image_path))
    if img is None:
        raise ValueError(f"Cannot open image: {image_path}")
    return img


def _quality_gate(img: np.ndarray) -> Dict[str, Union[bool, float, str]]:
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    lap_var = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    mean_intensity = float(np.mean(gray))
    std_intensity = float(np.std(gray))

    # Simple skew estimate from dominant Hough lines
    edges = cv2.Canny(gray, 50, 150)
    lines = cv2.HoughLinesP(edges, 1, np.pi / 180, threshold=60, minLineLength=60, maxLineGap=8)
    angles = []
    if lines is not None:
        # OpenCV 4 returns shape (N, 1, 4); OpenCV 5 returns (N, 4).
        for x1, y1, x2, y2 in np.asarray(lines).reshape(-1, 4)[:100]:
            angle = np.degrees(np.arctan2(y2 - y1, x2 - x1))
            if -45 <= angle <= 45:
                angles.append(abs(float(angle)))
    skew_abs_deg = float(np.median(angles)) if angles else 0.0

    blur_ok = lap_var >= 80.0
    exposure_ok = 45.0 <= mean_intensity <= 215.0
    contrast_ok = std_intensity >= 25.0
    skew_ok = skew_abs_deg <= 8.0
    passed = blur_ok and exposure_ok and contrast_ok and skew_ok

    reasons = []
    if not blur_ok:
        reasons.append("image_blurry")
    if not exposure_ok:
        reasons.append("bad_exposure")
    if not contrast_ok:
        reasons.append("low_contrast")
    if not skew_ok:
        reasons.append("label_skewed")

    return {
        "passed": passed,
        "blur_score": round(lap_var, 2),
        "mean_intensity": round(mean_intensity, 2),
        "contrast_score": round(std_intensity, 2),
        "skew_degrees": round(skew_abs_deg, 2),
        "reason": ",".join(reasons) if reasons else "ok",
    }


def _apply_exif_orientation(image_path: Union[str, Path], fallback: np.ndarray) -> np.ndarray:
    if PILImage is None:
        return fallback
    try:
        with PILImage.open(str(image_path)) as source:
            corrected = PILImageOps.exif_transpose(source).convert("RGB")
            array = np.asarray(corrected)
        return cv2.cvtColor(array, cv2.COLOR_RGB2BGR)
    except Exception:
        return fallback


def _normalize_label_view(img: np.ndarray) -> np.ndarray:
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
    l_channel, a_channel, b_channel = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=2.2, tileGridSize=(8, 8))
    l_enhanced = clahe.apply(l_channel)
    merged = cv2.merge((l_enhanced, a_channel, b_channel))
    return cv2.cvtColor(merged, cv2.COLOR_LAB2BGR)


def _order_points(points: np.ndarray) -> np.ndarray:
    rect = np.zeros((4, 2), dtype="float32")
    sums = points.sum(axis=1)
    diffs = np.diff(points, axis=1)
    rect[0] = points[np.argmin(sums)]
    rect[2] = points[np.argmax(sums)]
    rect[1] = points[np.argmin(diffs)]
    rect[3] = points[np.argmax(diffs)]
    return rect


def _warp_label_region(img: np.ndarray) -> tuple[np.ndarray, Dict[str, Union[bool, float, str]]]:
    height, width = img.shape[:2]
    working_width = min(width, 1600)
    scale = working_width / float(width) if width > working_width else 1.0
    working = (
        cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
        if scale != 1.0
        else img.copy()
    )

    gray = cv2.cvtColor(working, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blurred, 40, 120)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    closed = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, kernel, iterations=2)

    contours, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    contour_candidates = sorted(contours, key=cv2.contourArea, reverse=True)
    source_points: Optional[np.ndarray] = None
    source_method = "fallback_center_crop"

    for contour in contour_candidates[:12]:
        area = cv2.contourArea(contour)
        if area < (working.shape[0] * working.shape[1]) * 0.03:
            continue
        perimeter = cv2.arcLength(contour, True)
        approx = cv2.approxPolyDP(contour, 0.02 * perimeter, True)
        if len(approx) == 4:
            source_points = approx.reshape(4, 2).astype("float32")
            source_method = "contour_quad"
            break

    if source_points is None and contour_candidates:
        rect = cv2.minAreaRect(contour_candidates[0])
        source_points = cv2.boxPoints(rect).astype("float32")
        source_method = "min_area_rect"

    if source_points is None:
        crop_w = int(width * 0.84)
        crop_h = int(height * 0.72)
        left = max(0, (width - crop_w) // 2)
        top = max(0, (height - crop_h) // 2)
        right = min(width, left + crop_w)
        bottom = min(height, top + crop_h)
        cropped = img[top:bottom, left:right].copy()
        if cropped.size == 0:
            return img.copy(), {
                "flattened": False,
                "label_region_source": "full_image",
                "label_region_reason": "fallback_crop_failed",
            }
        return cropped, {
            "flattened": False,
            "label_region_source": source_method,
            "label_region_reason": "center_crop",
        }

    ordered = _order_points(source_points)
    (tl, tr, br, bl) = ordered
    width_a = np.linalg.norm(br - bl)
    width_b = np.linalg.norm(tr - tl)
    max_width = int(max(width_a, width_b))
    height_a = np.linalg.norm(tr - br)
    height_b = np.linalg.norm(tl - bl)
    max_height = int(max(height_a, height_b))

    if max_width < 60 or max_height < 60:
        cropped = img.copy()
        return cropped, {
            "flattened": False,
            "label_region_source": source_method,
            "label_region_reason": "candidate_too_small",
        }

    dst = np.array(
        [
            [0, 0],
            [max_width - 1, 0],
            [max_width - 1, max_height - 1],
            [0, max_height - 1],
        ],
        dtype="float32",
    )
    transform = cv2.getPerspectiveTransform(ordered, dst)
    warped = cv2.warpPerspective(working, transform, (max_width, max_height))

    if scale != 1.0:
        warped = cv2.resize(warped, None, fx=1.0 / scale, fy=1.0 / scale, interpolation=cv2.INTER_CUBIC)

    return warped, {
        "flattened": True,
        "label_region_source": source_method,
        "label_region_reason": "warped",
    }


def _encode_preview_image(img: np.ndarray) -> str:
    preview = img
    height, width = img.shape[:2]
    max_side = max(height, width)
    if max_side > 1400:
        scale = 1400 / float(max_side)
        preview = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    ok, encoded = cv2.imencode(".jpg", preview, [cv2.IMWRITE_JPEG_QUALITY, 90])
    if not ok:
        raise RuntimeError("Failed to encode label preview image")
    return base64.b64encode(encoded.tobytes()).decode("ascii")


def compose_flattened_label_from_images(images: list[np.ndarray]) -> tuple[np.ndarray, Dict[str, object]]:
    """Build a single flattened label image by combining multiple warped frames."""
    if not images:
        raise ValueError("No images provided for label composition")

    warped_images: list[np.ndarray] = []
    region_metadata: list[Dict[str, Union[bool, float, str]]] = []
    for img in images:
        warped, meta = _warp_label_region(img)
        if warped.size == 0:
            continue
        warped_images.append(warped)
        region_metadata.append(meta)

    if not warped_images:
        raise ValueError("Could not detect any label regions from provided frames")

    max_h = max(im.shape[0] for im in warped_images)
    max_w = max(im.shape[1] for im in warped_images)
    gray_stack: list[np.ndarray] = []
    for warped in warped_images:
        resized = cv2.resize(warped, (max_w, max_h), interpolation=cv2.INTER_CUBIC)
        gray = cv2.cvtColor(resized, cv2.COLOR_BGR2GRAY)
        gray_stack.append(gray)

    stack = np.stack(gray_stack, axis=0)
    # Lower percentile keeps darker ink strokes if text appears in only some frames.
    composite_gray = np.percentile(stack, 35, axis=0).astype(np.uint8)
    composite = cv2.cvtColor(composite_gray, cv2.COLOR_GRAY2BGR)

    return composite, {
        "composite": True,
        "source_frames": len(images),
        "used_frames": len(warped_images),
        "method": "percentile35_gray",
        "regions": region_metadata,
    }


from backend_api.services.drug_dictionary import validate_drug_name

PARSER_NAME = "adhera_label_parser"

_STRENGTH = re.compile(
    r"\b\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|iu|units?|%)(?:\s*/\s*\d*\.?\d*\s*(?:ml|g))?\b", re.I
)
_DIRECTION_START = re.compile(
    r"^\s*(take|apply|inhale|use|insert|place|instill|chew|dissolve|inject|swallow|give|spray|rub)\b", re.I
)
_REFILLS = re.compile(r"\brefills?\b(?:\s*(?:remaining|left))?\s*[:#]?\s*(\d+|no|none)\b", re.I)
_PRESCRIBER = re.compile(r"\b(?:dr\.?|prescriber|prescribed by|presc)\s*[:.]?\s+([a-z][a-z.' -]{1,40})", re.I)
_PHARMACY = re.compile(r"pharmacy|cvs|walgreens|rite aid|walmart|costco|kaiser|safeway|kroger|target", re.I)
_FIELD_LINE = re.compile(
    r"\b(rx\s*#?|qty|quantity|refills?|dr\.?|prescriber|pharmacy|date|filled|exp|discard|ndc|mfg)\b", re.I
)
_FORM_WORDS = re.compile(
    r"\b(tabs?|tablets?|caps?|capsules?|er|xr|sr|dr|hcl|oral|solution|suspension|cream|ointment)\b", re.I
)


def _lines(text: str) -> list[str]:
    seen: set[str] = set()
    lines = []
    for raw in text.splitlines():
        line = " ".join(raw.split())
        key = line.lower()
        if line and key not in seen:
            seen.add(key)
            lines.append(line)
    return lines


def _drug_candidate(line: str) -> str:
    name = _STRENGTH.sub(" ", line)
    name = _FORM_WORDS.sub(" ", name)
    name = re.sub(r"[^A-Za-z -]", " ", name)
    return " ".join(name.split())


def _extract_instructions(lines: list[str]) -> str:
    for index, line in enumerate(lines):
        if _DIRECTION_START.match(line):
            parts = [line]
            for follow in lines[index + 1 : index + 4]:
                if (
                    _FIELD_LINE.search(follow)
                    or _STRENGTH.search(follow)
                    and not _DIRECTION_START.match(follow)
                ):
                    break
                parts.append(follow)
            return " ".join(parts)
    return ""


def _extract_medication(lines: list[str]) -> tuple[str, str, dict[str, object]]:
    """Return (raw line, dosage, match) for the most likely drug line.

    Lines that include a strength are tried first, then other short lines.
    """
    with_strength = [line for line in lines if _STRENGTH.search(line) and not _DIRECTION_START.match(line)]
    others = [
        line
        for line in lines
        if line not in with_strength
        and not _DIRECTION_START.match(line)
        and not _FIELD_LINE.search(line)
        and 3 <= len(line) <= 40
    ]
    best: tuple[str, str, dict[str, object]] = ("", "", {})
    best_score = -1.0
    for line in (with_strength + others)[:8]:
        candidate = _drug_candidate(line)
        if len(candidate) < 3:
            continue
        match = validate_drug_name(candidate)
        score = match.score + (5.0 if line in with_strength else 0.0)
        if score > best_score:
            strength = _STRENGTH.search(line)
            best_score = score
            best = (
                candidate,
                strength.group(0) if strength else "",
                {
                    "name": match.snapped_name,
                    "matched": match.matched,
                    "score": match.score,
                    "confidence": match.confidence,
                    "source": match.source,
                    "rxcui": match.rxcui or None,
                },
            )
        if match.matched and line in with_strength:
            break
    return best


def parse_label_text(text: str) -> Dict[str, object]:
    """Extract prescription fields from label text recognized on the phone."""
    lines = _lines(text or "")
    raw_name, dosage, match = _extract_medication(lines)
    if not dosage:
        strength = next((m.group(0) for m in map(_STRENGTH.search, lines) if m), "")
        dosage = strength

    refills = ""
    prescriber = ""
    pharmacy = ""
    for line in lines:
        if not refills and (m := _REFILLS.search(line)):
            refills = "0" if m.group(1).lower() in {"no", "none"} else m.group(1)
        if not prescriber and (m := _PRESCRIBER.search(line)):
            prescriber = m.group(1).strip(" .").title()
        if not pharmacy and _PHARMACY.search(line):
            pharmacy = line

    instructions = _extract_instructions(lines)
    matched = bool(match.get("matched"))
    return {
        "medication_name": str(match.get("name") or raw_name),
        "dosage": dosage,
        "instructions": instructions,
        "medication_name_raw": raw_name,
        "medication_name_confidence": str(match.get("confidence") or "low"),
        "medication_name_matched": matched,
        "medication_name_match_score": float(match.get("score") or 0.0),
        "medication_name_source": str(match.get("source") or "none"),
        "medication_name_rxcui": match.get("rxcui"),
        "refills_remaining": refills,
        "prescribed_by": prescriber,
        "pharmacy": pharmacy,
        "requires_human_review": not (matched and instructions),
    }


def scan_prescription_label_multi_views(
    image_paths: List[Union[str, Path]],
    device_ocr_text: Optional[str] = None,
    device_ocr_provider: Optional[str] = None,
) -> Dict[str, object]:
    if not image_paths:
        raise ValueError("No images were provided for semantic fusion scan")

    normalized_views: List[np.ndarray] = []
    for image_path in image_paths:
        original = _load_image(image_path)
        oriented = _apply_exif_orientation(image_path, original)
        cropped, _ = _warp_label_region(oriented)
        normalized = _normalize_label_view(cropped)
        normalized_views.append(normalized)

    parsed_dict = parse_label_text(device_ocr_text or "")

    # Generate preview from the first flattened frame
    flattened, _ = _warp_label_region(_apply_exif_orientation(image_paths[0], _load_image(image_paths[0])))
    parsed_dict["label_preview_base64"] = _encode_preview_image(flattened)
    parsed_dict["raw_text"] = device_ocr_text or ""
    parsed_dict["ocr_provider_chain"] = [device_ocr_provider or "device_ocr", PARSER_NAME]
    parsed_dict["quality_gate"] = _quality_gate(normalized_views[0]) if normalized_views else {}

    return parsed_dict


def scan_prescription_label(
    image_path: Union[str, Path],
    device_ocr_text: Optional[str] = None,
    device_ocr_provider: Optional[str] = None,
) -> Dict[str, object]:
    return scan_prescription_label_multi_views([image_path], device_ocr_text, device_ocr_provider)
