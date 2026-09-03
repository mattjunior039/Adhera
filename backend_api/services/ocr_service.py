"""Hybrid OCR pipeline for prescription label scanning.

Pipeline goals:
- quality control gate before OCR
- automatic label-region flattening and crop before OCR
- hybrid OCR provider fallback: Google Vision -> device hint text -> Tesseract
- deterministic field extraction and SIG normalization
- optional constrained local-LLM normalization and low-confidence field recovery
"""
from __future__ import annotations

import base64
import json
import os
import re
from pathlib import Path
from typing import Dict, Optional, Union

import cv2
import numpy as np

try:
    import httpx
except ImportError:
    httpx = None  # type: ignore[assignment]

PILImage = None
pytesseract = None
try:
    import pytesseract  # type: ignore[import-not-found]
    from PIL import Image as PILImage  # type: ignore[import-not-found]
    _TESSERACT_OK = True
except ImportError:
    _TESSERACT_OK = False

vision = None
try:
    from google.cloud import vision  # type: ignore[import-not-found]
    _GCV_OK = True
except ImportError:
    _GCV_OK = False

try:
    from backend_api.services.drug_dictionary import match_to_dict
except ImportError:
    from services.drug_dictionary import match_to_dict

SIG_DICT: Dict[str, str] = {
    "po": "oral",
    "pr": "rectal",
    "sl": "sublingual",
    "bid": "twice daily",
    "tid": "3 times daily",
    "qid": "4 times daily",
    "qhs": "at bedtime",
    "qam": "every morning",
    "qpm": "every evening",
    "prn": "as needed",
    "qd": "daily",
    "qod": "every other day",
}

_DOSE_WORDS: Dict[str, float] = {
    "half": 0.5,
    "one": 1.0,
    "two": 2.0,
    "three": 3.0,
    "four": 4.0,
}

_GENERIC_DOSAGE_FORMS = {
    "tab",
    "tabs",
    "tablet",
    "tablets",
    "cap",
    "caps",
    "capsule",
    "capsules",
    "ml",
    "units",
}


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
        for line in lines[:100]:
            x1, y1, x2, y2 = line[0]
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


def _preprocess_for_ocr(img: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    h, w = gray.shape
    if max(h, w) < 1400:
        scale = 1400 / max(h, w)
        gray = cv2.resize(gray, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
    denoise = cv2.bilateralFilter(gray, d=7, sigmaColor=55, sigmaSpace=55)
    return cv2.adaptiveThreshold(
        denoise,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        35,
        9,
    )


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
    working = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA) if scale != 1.0 else img.copy()

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

    dst = np.array([
        [0, 0],
        [max_width - 1, 0],
        [max_width - 1, max_height - 1],
        [0, max_height - 1],
    ], dtype="float32")
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


def _ocr_with_tesseract(img: np.ndarray) -> str:
    if not _TESSERACT_OK or PILImage is None or pytesseract is None:
        raise RuntimeError(
            "pytesseract / Tesseract is not installed. "
            "Install: pip install pytesseract Pillow and brew install tesseract"
        )
    pre = _preprocess_for_ocr(img)
    pil_img = PILImage.fromarray(pre)
    return pytesseract.image_to_string(pil_img, config="--oem 3 --psm 6")


def _center_weighted_text_from_annotations(response: object, width: int, height: int) -> str:
    annotations = getattr(response, "text_annotations", None) or []
    if len(annotations) <= 1:
        return ""

    focus_items: list[tuple[float, float, str]] = []
    for ann in annotations[1:]:
        text = (getattr(ann, "description", "") or "").strip()
        if not text:
            continue
        poly = getattr(ann, "bounding_poly", None)
        vertices = getattr(poly, "vertices", None) if poly is not None else None
        if not vertices:
            continue

        xs: list[float] = []
        ys: list[float] = []
        for v in vertices:
            x = getattr(v, "x", None)
            y = getattr(v, "y", None)
            if x is None or y is None:
                continue
            xs.append(float(x))
            ys.append(float(y))
        if not xs or not ys or width <= 0 or height <= 0:
            continue

        cx = sum(xs) / len(xs)
        cy = sum(ys) / len(ys)
        nx = cx / float(width)
        ny = cy / float(height)

        # Non-destructive spatial filter: retain broad central area while
        # preserving context from full-image OCR output.
        if 0.12 <= nx <= 0.88 and 0.05 <= ny <= 0.95:
            focus_items.append((cy, cx, text))

    if not focus_items:
        return ""

    focus_items.sort(key=lambda item: (item[0], item[1]))
    row_tol = max(12.0, float(height) * 0.018)
    lines: list[list[str]] = []
    current_line: list[str] = []
    current_y: Optional[float] = None

    for cy, _cx, token in focus_items:
        if current_y is None or abs(cy - current_y) <= row_tol:
            current_line.append(token)
            current_y = cy if current_y is None else (current_y + cy) / 2.0
            continue
        lines.append(current_line)
        current_line = [token]
        current_y = cy

    if current_line:
        lines.append(current_line)

    return "\n".join(" ".join(line).strip() for line in lines if line)


def _ocr_with_google_vision(img: np.ndarray) -> Dict[str, str]:
    if not _GCV_OK or vision is None:
        raise RuntimeError("google-cloud-vision is not installed")
    if not os.getenv("GOOGLE_APPLICATION_CREDENTIALS"):
        raise RuntimeError("GOOGLE_APPLICATION_CREDENTIALS not set")
    ok, encoded = cv2.imencode(".jpg", img)
    if not ok:
        raise RuntimeError("Failed to encode image for Google Vision")
    client = vision.ImageAnnotatorClient()
    gimg = vision.Image(content=encoded.tobytes())
    response = client.document_text_detection(image=gimg)
    if response.error.message:
        raise RuntimeError(response.error.message)
    full_text = ""
    if response.text_annotations:
        full_text = response.text_annotations[0].description or ""
    h, w = img.shape[:2]
    focus_text = _center_weighted_text_from_annotations(response, w, h)
    return {
        "full_text": full_text,
        "focus_text": focus_text,
    }


def _normalize_whitespace(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def _parse_dose_quantity(token: str) -> Optional[float]:
    if not token:
        return None
    raw = token.strip().lower()
    if raw in _DOSE_WORDS:
        return _DOSE_WORDS[raw]
    if re.fullmatch(r"\d+(?:\.\d+)?", raw):
        try:
            return float(raw)
        except ValueError:
            return None
    if re.fullmatch(r"\d+\s*/\s*\d+", raw):
        left, right = raw.split("/")
        try:
            denominator = float(right)
            if denominator == 0:
                return None
            return float(left) / denominator
        except ValueError:
            return None
    return None


def _should_fallback_from_cloud_error(error_text: str) -> bool:
    msg = error_text.lower()
    return any(
        needle in msg
        for needle in (
            "quota",
            "resource_exhausted",
            "deadline",
            "timed out",
            "timeout",
            "unavailable",
            "connection",
            "socket",
            "503",
            "429",
        )
    )


def _field_confidence_score(parsed: Dict[str, object]) -> int:
    score = 0
    if str(parsed.get("medication_name") or "").strip():
        score += 1
    if str(parsed.get("dosage") or "").strip():
        score += 1
    if str(parsed.get("instructions") or "").strip():
        score += 1
    if str(parsed.get("refills_remaining") or "").strip():
        score += 1
    return score


def _extract_fields_with_local_llm(raw_text: str) -> Optional[Dict[str, object]]:
    endpoint = os.getenv("LOCAL_SIG_LLM_ENDPOINT", "").strip()
    if not endpoint or httpx is None:
        return None

    max_chars = int(os.getenv("LOCAL_FIELD_LLM_MAX_CHARS", "6000"))
    prompt = (
        "You are extracting prescription label fields. "
        "Return only strict JSON with keys: medication_name, dosage, instructions, refills. "
        "Each value must be string or null, except refills which must be integer or null. "
        "Do not infer missing values.\n\n"
        "Raw OCR text:\n"
        f"{raw_text[:max_chars]}"
    )
    payload = {
        "model": os.getenv("LOCAL_SIG_LLM_MODEL", "llama3:8b"),
        "prompt": prompt,
        "stream": False,
    }

    try:
        response = httpx.post(endpoint, json=payload, timeout=10.0)
        response.raise_for_status()
        body = response.json()
        content = body.get("response", "")
        obj = json.loads(content)
        if not isinstance(obj, dict):
            return None

        refills_value = obj.get("refills")
        refills: Optional[str] = None
        if isinstance(refills_value, int):
            refills = str(refills_value)
        elif isinstance(refills_value, str) and refills_value.strip().isdigit():
            refills = refills_value.strip()

        return {
            "medication_name": obj.get("medication_name") if isinstance(obj.get("medication_name"), str) else None,
            "dosage": obj.get("dosage") if isinstance(obj.get("dosage"), str) else None,
            "instructions": obj.get("instructions") if isinstance(obj.get("instructions"), str) else None,
            "refills_remaining": refills,
        }
    except Exception:
        return None


def _normalize_sig_deterministic(raw: str) -> Dict[str, Union[bool, float, int, str, None]]:
    text = _normalize_whitespace(raw.lower())
    tokens = re.findall(r"[a-z0-9/.]+", text)
    mapped = [SIG_DICT[t] if t in SIG_DICT else t for t in tokens]
    mapped_text = " ".join(mapped)

    dose: Optional[int] = None
    dose_float: Optional[float] = None
    dose_text: Optional[str] = None
    dose_unit: Optional[str] = None
    dose_match = re.search(
        r"(?:take\s+)?(\d+\s*/\s*\d+|\d+(?:\.\d+)?|half|one|two|three|four)\s*"
        r"(tab(?:s)?|tablet(?:s)?|cap(?:sule)?(?:s)?|puff(?:s)?|ml|teaspoon(?:s)?|tsp)?",
        mapped_text,
    )
    if dose_match:
        dose_text = dose_match.group(1)
        dose_unit = dose_match.group(2)
        if dose_text:
            dose_float = _parse_dose_quantity(dose_text)
        if dose_float is not None and float(dose_float).is_integer():
            dose = int(dose_float)

    route = "oral" if ("oral" in mapped_text or "by mouth" in mapped_text or "mouth" in mapped_text) else None
    frequency = None
    qh_match = re.search(r"\bq\s*(\d{1,2})h\b", mapped_text)
    every_hours_match = re.search(r"\bevery\s+(\d{1,2})\s*hours?\b", mapped_text)
    if qh_match:
        frequency = f"every {int(qh_match.group(1))} hours"
    elif every_hours_match:
        frequency = f"every {int(every_hours_match.group(1))} hours"
    elif "3 times daily" in mapped_text:
        frequency = "3 times daily"
    elif "twice daily" in mapped_text:
        frequency = "twice daily"
    elif "4 times daily" in mapped_text:
        frequency = "4 times daily"
    elif "once daily" in mapped_text:
        frequency = "daily"
    elif "daily" in mapped_text:
        frequency = "daily"
    elif "at bedtime" in mapped_text:
        frequency = "at bedtime"

    as_needed = "as needed" in mapped_text

    return {
        "raw": raw,
        "normalized_text": mapped_text,
        "dose": dose,
        "dose_float": dose_float,
        "dose_text": dose_text,
        "dose_unit": dose_unit,
        "route": route,
        "frequency": frequency,
        "as_needed": as_needed,
    }


def _normalize_sig_with_local_llm(raw: str, deterministic: Dict[str, Union[bool, float, int, str, None]]) -> Dict[str, Union[bool, float, int, str, None]]:
    endpoint = os.getenv("LOCAL_SIG_LLM_ENDPOINT", "").strip()
    if not endpoint or httpx is None:
        return deterministic

    prompt = (
        "Normalize this prescription SIG into strict JSON with keys "
        "dose(int|null), route(string|null), frequency(string|null), as_needed(bool). "
        "Do not invent values. If unsure, return null. SIG: "
        f"{raw}"
    )
    payload = {
        "model": os.getenv("LOCAL_SIG_LLM_MODEL", "llama3:8b"),
        "prompt": prompt,
        "stream": False,
    }

    try:
        response = httpx.post(endpoint, json=payload, timeout=8.0)
        response.raise_for_status()
        body = response.json()
        text = body.get("response", "")
        llm_data = json.loads(text)
        candidate = {
            "raw": raw,
            "normalized_text": deterministic.get("normalized_text"),
            "dose": llm_data.get("dose"),
            "route": llm_data.get("route"),
            "frequency": llm_data.get("frequency"),
            "as_needed": llm_data.get("as_needed"),
        }

        # Guardrail: never let LLM invent if deterministic already has stronger value.
        if deterministic.get("dose") is not None and candidate.get("dose") != deterministic.get("dose"):
            candidate["dose"] = deterministic.get("dose")
        if deterministic.get("route") and not candidate.get("route"):
            candidate["route"] = deterministic.get("route")
        if deterministic.get("frequency") and not candidate.get("frequency"):
            candidate["frequency"] = deterministic.get("frequency")
        if deterministic.get("as_needed") is True:
            candidate["as_needed"] = True
        return candidate
    except Exception:
        return deterministic


def _parse_label_fields(text: str) -> Dict[str, object]:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    full = "\n".join(lines)

    dosage_match = re.search(
        r"\b(\d+(?:\.\d+)?\s*(?:mg(?:/m[lL])?|mcg|g\b|iu|units?|tablet|cap(?:sule)?|ml)s?)\b",
        full,
        re.IGNORECASE,
    )
    dosage = dosage_match.group(1).strip() if dosage_match else ""

    instr_match = re.search(
        r"(take|apply|use|inject|inhale|swallow|instill)\b[^\n]{5,}",
        full,
        re.IGNORECASE,
    )
    instructions = instr_match.group(0).strip() if instr_match else ""
    if not instructions:
        for line in lines:
            if re.search(r"\b(?:bid|tid|qid|qhs|qam|qpm|prn|qd|qod|q\d{1,2}h|every\s+\d+\s+hours?)\b", line, re.IGNORECASE):
                instructions = line
                break

    refills_match = re.search(r"refills?\s*(?:remaining)?\s*[:\-]?\s*(\d+|no\s+refills?|none)", full, re.IGNORECASE)
    refills = refills_match.group(1) if refills_match else None

    prescriber_match = re.search(r"(?:prescrib(?:er|ed\s+by)\s*[:\-]?\s*|Dr\.?\s+)([A-Z][a-zA-Z\-\.\s]{2,40})", full)
    prescriber = prescriber_match.group(0).strip() if prescriber_match else None

    pharmacy = next((line for line in lines if re.search(r"pharm(?:acy)?", line, re.IGNORECASE)), None)
    if pharmacy is None and lines:
        pharmacy = lines[0]

    dosage_prefix_name = re.compile(
        r"^\d+(?:\.\d+)?\s*(?:mg(?:/m[lL])?|mcg|g|iu|units?)\s+([A-Za-z][A-Za-z0-9\-\s]{1,60})$",
        re.IGNORECASE,
    )
    name_prefix_dosage = re.compile(
        r"^([A-Za-z][A-Za-z0-9\-\s]{1,60})\s+\d+(?:\.\d+)?\s*(?:mg(?:/m[lL])?|mcg|g|iu|units?)$",
        re.IGNORECASE,
    )

    med_name = ""
    for line in lines:
        clean = _normalize_whitespace(line)
        m1 = dosage_prefix_name.match(clean)
        if m1:
            candidate = m1.group(1).strip()
            if candidate.lower() not in _GENERIC_DOSAGE_FORMS:
                med_name = candidate
                break
        m2 = name_prefix_dosage.match(clean)
        if m2:
            candidate = m2.group(1).strip()
            if candidate.lower() not in _GENERIC_DOSAGE_FORMS:
                med_name = candidate
                break

    skip = re.compile(
        r"^(\d|take |apply |use |refill|qty|pharm|prescrib|patient|rx\s*#|date|dob|dr\.?\s)",
        re.IGNORECASE,
    )
    for line in lines:
        if len(line) > 3 and not skip.match(line) and line != pharmacy:
            if not med_name:
                med_name = line
                break

    return {
        "medication_name": med_name,
        "dosage": dosage,
        "instructions": instructions,
        "refills_remaining": refills,
        "prescribed_by": prescriber,
        "pharmacy": pharmacy,
    }


def scan_prescription_label(
    image_path: Union[str, Path],
    device_ocr_text: Optional[str] = None,
    device_ocr_provider: Optional[str] = None,
) -> Dict[str, object]:
    img = _load_image(image_path)
    label_img, label_region = _warp_label_region(img)
    quality = _quality_gate(label_img)

    ocr_sources: list[str] = []
    raw_text = ""
    full_cloud_text = ""
    focus_cloud_text = ""
    cloud_error = ""

    try:
        gcv = _ocr_with_google_vision(label_img)
        full_cloud_text = (gcv.get("full_text") or "").strip()
        focus_cloud_text = (gcv.get("focus_text") or "").strip()
        if full_cloud_text:
            raw_text = full_cloud_text
            ocr_sources.append("google_cloud_vision_document")
    except Exception as exc:
        print("❌ CLOUD VISION FAILED:")
        print(exc)
        cloud_error = str(exc)

    fallback_allowed = bool(cloud_error) and _should_fallback_from_cloud_error(cloud_error)
    if fallback_allowed and device_ocr_text and device_ocr_text.strip():
        raw_text = device_ocr_text.strip()
        ocr_sources.append(device_ocr_provider or "device_hint")

    if fallback_allowed and not raw_text:
        raw_text = _ocr_with_tesseract(label_img)
        if raw_text.strip():
            ocr_sources.append("tesseract")

    if not raw_text.strip():
        if cloud_error:
            raise RuntimeError(f"Cloud Vision failed and no fallback OCR text was available: {cloud_error}")
        raise ValueError("OCR returned no readable text")

    parse_source_text = focus_cloud_text if focus_cloud_text else raw_text
    parsed = _parse_label_fields(parse_source_text)
    if focus_cloud_text and full_cloud_text:
        parsed_full = _parse_label_fields(full_cloud_text)
        if _field_confidence_score(parsed_full) > _field_confidence_score(parsed):
            parsed = parsed_full

    medication_name_value = parsed.get("medication_name")
    medication_name = medication_name_value if isinstance(medication_name_value, str) else None
    name_match = match_to_dict(medication_name, threshold=85.0)

    low_confidence_parse = (
        _field_confidence_score(parsed) < 3
        or not bool(name_match.get("matched"))
        or not bool(str(parsed.get("instructions") or "").strip())
    )
    if low_confidence_parse:
        llm_fields = _extract_fields_with_local_llm(raw_text)
        if llm_fields is not None:
            for key in ("medication_name", "dosage", "instructions", "refills_remaining"):
                current_value = str(parsed.get(key) or "").strip()
                llm_value = llm_fields.get(key)
                if not current_value and isinstance(llm_value, str) and llm_value.strip():
                    parsed[key] = llm_value.strip()

            medication_name_value = parsed.get("medication_name")
            medication_name = medication_name_value if isinstance(medication_name_value, str) else None
            name_match = match_to_dict(medication_name, threshold=85.0)

    parsed["medication_name_raw"] = name_match["raw_name"]
    parsed["medication_name"] = name_match["snapped_name"]
    parsed["medication_name_match_score"] = name_match["score"]
    parsed["medication_name_confidence"] = name_match["confidence"]
    parsed["medication_name_matched"] = name_match["matched"]
    parsed["medication_name_source"] = name_match.get("source")
    parsed["medication_name_rxcui"] = name_match.get("rxcui")

    instructions_text = str(parsed.get("instructions") or "")
    deterministic_sig = _normalize_sig_deterministic(instructions_text)
    normalized_sig = _normalize_sig_with_local_llm(instructions_text, deterministic_sig)

    parsed["quality_gate"] = quality
    parsed["label_region"] = label_region
    parsed["label_preview_base64"] = _encode_preview_image(label_img)
    parsed["ocr_provider_chain"] = ocr_sources
    parsed["raw_text"] = raw_text
    if cloud_error:
        parsed["cloud_vision_error"] = cloud_error
    parsed["normalized_sig"] = normalized_sig
    parsed["requires_human_review"] = (
        (not bool(quality.get("passed")))
        or not bool(name_match["matched"])
        or not bool(parsed.get("medication_name"))
        or not bool(parsed.get("instructions"))
    )
    return parsed
