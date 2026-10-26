"""Hybrid OCR pipeline for prescription label scanning using Google Cloud Vision.

Pipeline:
- quality control gate (blur, exposure, contrast, skew) before OCR
- automatic label-region flattening and crop before OCR
- hybrid OCR provider chain: Google Cloud Vision document OCR -> device hint text -> Tesseract
- deterministic field extraction, SIG normalization, and NIH RxNorm drug-name matching
"""

from __future__ import annotations

import base64
import json
import os
import re
from pathlib import Path
from typing import Dict, List, Optional, Union

import cv2
import numpy as np

from backend_api.services.drug_dictionary import match_to_dict, validate_drug_name

try:
    import httpx
except ImportError:
    httpx = None  # type: ignore[assignment]

PILImage = None
PILImageOps = None
pytesseract = None
try:
    from PIL import Image as PILImage  # type: ignore[import-not-found]
    from PIL import ImageOps as PILImageOps  # type: ignore[import-not-found]
except ImportError:
    pass

try:
    import pytesseract  # type: ignore[import-not-found]

    _TESSERACT_OK = PILImage is not None
except ImportError:
    _TESSERACT_OK = False

vision = None
try:
    from google.cloud import vision  # type: ignore[import-not-found]

    _GCV_OK = True
except ImportError:
    _GCV_OK = False

PARSER_NAME = "adhera_label_parser"

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

_STRENGTH = re.compile(
    r"\b\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|iu|units?|%)(?:\s*/\s*\d*\.?\d*\s*(?:ml|g))?\b", re.I
)
_DIRECTION_START = re.compile(
    r"^\s*(take|apply|inhale|use|insert|place|instill|chew|dissolve|inject|swallow|give|spray|rub)\b",
    re.I,
)
_ABBREV_SIG = re.compile(
    r"\b(?:bid|tid|qid|qhs|qam|qpm|prn|qd|qod|q\d{1,2}h|every\s+\d+\s+hours?)\b",
    re.I,
)
_REFILLS = re.compile(
    r"\brefills?\b(?:\s*(?:remaining|left))?\s*[:#\-]?\s*(\d+|no\s+refills?|no|none)\b", re.I
)
_PRESCRIBER = re.compile(
    r"\b(?:dr\.?|prescriber|prescribed\s+by|presc)\s*[:.\-]?\s*([a-z][a-z.' \-]{1,40})",
    re.I,
)
_PHARMACY = re.compile(
    r"pharm(?:acy)?|cvs|walgreens|rite aid|walmart|costco|kaiser|safeway|kroger|target",
    re.I,
)
_FIELD_LINE = re.compile(
    r"\b(rx\s*#?|qty|quantity|refills?|dr\.?|prescriber|pharmacy|date|filled|exp|discard|ndc|mfg)\b",
    re.I,
)
_FORM_WORDS = re.compile(
    r"\b(tabs?|tablets?|caps?|capsules?|er|xr|sr|dr|hcl|oral|solution|suspension|cream|ointment)\b",
    re.I,
)


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
    if PILImage is None or PILImageOps is None:
        return fallback
    try:
        with PILImage.open(str(image_path)) as source:
            corrected = PILImageOps.exif_transpose(source).convert("RGB")
            array = np.asarray(corrected)
        return cv2.cvtColor(array, cv2.COLOR_RGB2BGR)
    except Exception:
        return fallback


def _normalize_for_cloud_ocr(img: np.ndarray) -> np.ndarray:
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
    l_channel, a_channel, b_channel = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=2.2, tileGridSize=(8, 8))
    l_enhanced = clahe.apply(l_channel)
    merged = cv2.merge((l_enhanced, a_channel, b_channel))
    return cv2.cvtColor(merged, cv2.COLOR_LAB2BGR)


_normalize_label_view = _normalize_for_cloud_ocr


def _preprocess_for_ocr(img: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)
    denoised = cv2.fastNlMeansDenoising(enhanced, h=10)
    thresh = cv2.adaptiveThreshold(denoised, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 10)
    return thresh


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
    min_contour_area = (working.shape[0] * working.shape[1]) * 0.03

    for contour in contour_candidates[:12]:
        area = cv2.contourArea(contour)
        if area < min_contour_area:
            continue
        perimeter = cv2.arcLength(contour, True)
        approx = cv2.approxPolyDP(contour, 0.02 * perimeter, True)
        if len(approx) == 4:
            source_points = approx.reshape(4, 2).astype("float32")
            source_method = "contour_quad"
            break

    if (
        source_points is None
        and contour_candidates
        and cv2.contourArea(contour_candidates[0]) >= min_contour_area
    ):
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


def _resolve_google_credentials_path() -> Optional[str]:
    env_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if env_path:
        candidate = Path(env_path)
        if candidate.is_file():
            return str(candidate.resolve())
        backend_relative = Path(__file__).resolve().parent.parent / env_path
        if backend_relative.is_file():
            return str(backend_relative.resolve())
    default_secret = Path(__file__).resolve().parent.parent / "secrets" / "google-credentials.json"
    if default_secret.is_file():
        return str(default_secret.resolve())
    return None


def _ocr_with_google_vision(img: np.ndarray) -> Dict[str, str]:
    if not _GCV_OK or vision is None:
        raise RuntimeError("google-cloud-vision is not installed")

    creds_path = _resolve_google_credentials_path()
    api_key = os.getenv("GOOGLE_CLOUD_VISION_API_KEY", os.getenv("GOOGLE_API_KEY", "")).strip()

    if creds_path:
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = creds_path
        client = vision.ImageAnnotatorClient.from_service_account_json(creds_path)
    elif api_key:
        client = vision.ImageAnnotatorClient(client_options={"api_key": api_key})
    else:
        raise RuntimeError("GOOGLE_APPLICATION_CREDENTIALS or GOOGLE_CLOUD_VISION_API_KEY not set")

    ok, encoded = cv2.imencode(".jpg", img)
    if not ok:
        raise RuntimeError("Failed to encode image for Google Vision")

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
            "network",
            "not installed",
            "not set",
            "credentials",
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
    bounded_text = raw_text[:max_chars]
    prompt = (
        "Extract prescription label fields into strict JSON with keys: "
        "medication_name (string|null), dosage (string|null), instructions (string|null), refills (int|null). "
        "Do not invent facts. If absent, use null. OCR_TEXT: "
        f"{bounded_text}"
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
            "medication_name": obj.get("medication_name")
            if isinstance(obj.get("medication_name"), str)
            else None,
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


def _normalize_sig_with_local_llm(
    raw: str, deterministic: Dict[str, Union[bool, float, int, str, None]]
) -> Dict[str, Union[bool, float, int, str, None]]:
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
            if _ABBREV_SIG.search(line):
                instructions = line
                break

    refills_match = re.search(
        r"refills?\s*(?:remaining)?\s*[:\-]?\s*(\d+|no\s+refills?|none)",
        full,
        re.IGNORECASE,
    )
    refills = refills_match.group(1) if refills_match else None

    prescriber_match = re.search(
        r"(?:prescrib(?:er|ed\s+by)\s*[:\-]?\s*|Dr\.?\s+)([A-Z][a-zA-Z\-\.\s]{2,40})",
        full,
    )
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
    for line in lines:
        if _ABBREV_SIG.search(line):
            return line
    return ""


def _extract_medication(lines: list[str]) -> tuple[str, str, dict[str, object]]:
    """Return (raw line, dosage, match) for the most likely drug line."""
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
    """Extract prescription fields from OCR text."""
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
            val = m.group(1).strip().lower()
            refills = "0" if val in {"no", "none"} or val.startswith("no ") else m.group(1).strip()
        if not prescriber and (m := _PRESCRIBER.search(line)):
            prescriber = m.group(1).strip(" .").title()
        if not pharmacy and _PHARMACY.search(line):
            pharmacy = line

    instructions = _extract_instructions(lines)
    matched = bool(match.get("matched"))
    deterministic_sig = _normalize_sig_deterministic(instructions)
    normalized_sig = _normalize_sig_with_local_llm(instructions, deterministic_sig)

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
        "normalized_sig": normalized_sig,
        "requires_human_review": not (matched and instructions),
    }


def scan_prescription_label_multi_views(
    image_paths: List[Union[str, Path]],
    device_ocr_text: Optional[str] = None,
    device_ocr_provider: Optional[str] = None,
) -> Dict[str, object]:
    if not image_paths:
        raise ValueError("No images were provided for semantic fusion scan")

    oriented_views: List[np.ndarray] = []
    warped_views: List[np.ndarray] = []
    label_region: Dict[str, Union[bool, float, str]] = {}

    for index, image_path in enumerate(image_paths):
        original = _load_image(image_path)
        oriented = _apply_exif_orientation(image_path, original)
        cropped, region_meta = _warp_label_region(oriented)
        if index == 0:
            label_region = dict(region_meta)
        oriented_views.append(_normalize_for_cloud_ocr(oriented))
        warped_views.append(_normalize_for_cloud_ocr(cropped))

    quality = _quality_gate(warped_views[0]) if warped_views else {}

    ocr_sources: list[str] = []
    full_cloud_chunks: list[str] = []
    focus_cloud_chunks: list[str] = []
    cloud_error = ""

    for warped_img, full_img in zip(warped_views, oriented_views):
        try:
            gcv = _ocr_with_google_vision(warped_img)
            full_text = (gcv.get("full_text") or "").strip()
            focus_text = (gcv.get("focus_text") or "").strip()
            if len(full_text) < 20:
                gcv_full = _ocr_with_google_vision(full_img)
                alt_full = (gcv_full.get("full_text") or "").strip()
                alt_focus = (gcv_full.get("focus_text") or "").strip()
                if len(alt_full) > len(full_text):
                    full_text = alt_full
                    focus_text = alt_focus
            if full_text:
                full_cloud_chunks.append(full_text)
            if focus_text:
                focus_cloud_chunks.append(focus_text)
        except Exception as exc:
            cloud_error = str(exc)
            break

    full_cloud_text = "\n".join(full_cloud_chunks).strip()
    focus_cloud_text = "\n".join(focus_cloud_chunks).strip()
    raw_text = ""

    if full_cloud_text:
        raw_text = full_cloud_text
        ocr_sources.append("google_cloud_vision_document")

    if not raw_text and device_ocr_text and device_ocr_text.strip():
        raw_text = device_ocr_text.strip()
        ocr_sources.append(device_ocr_provider or "device_ocr")

    if not raw_text and (not cloud_error or _should_fallback_from_cloud_error(cloud_error)):
        try:
            tess_text = _ocr_with_tesseract(warped_views[0]).strip()
            if tess_text:
                raw_text = tess_text
                ocr_sources.append("tesseract")
        except Exception:
            pass

    if not raw_text and cloud_error and not (device_ocr_text and device_ocr_text.strip()):
        raise RuntimeError(f"Cloud Vision failed and no fallback OCR text was available: {cloud_error}")

    ocr_sources.append(PARSER_NAME)

    parse_source_text = focus_cloud_text if focus_cloud_text else raw_text
    if device_ocr_text and device_ocr_text.strip() and full_cloud_text:
        combined_text = f"{full_cloud_text}\n{device_ocr_text.strip()}"
    else:
        combined_text = full_cloud_text or raw_text

    parsed = parse_label_text(parse_source_text)
    if combined_text and combined_text != parse_source_text:
        parsed_combined = parse_label_text(combined_text)
        if _field_confidence_score(parsed_combined) > _field_confidence_score(parsed) or (
            bool(parsed_combined.get("medication_name_matched"))
            and not bool(parsed.get("medication_name_matched"))
        ):
            parsed = parsed_combined

    low_confidence_parse = (
        _field_confidence_score(parsed) < 3
        or not bool(parsed.get("medication_name_matched"))
        or not bool(str(parsed.get("instructions") or "").strip())
    )
    if low_confidence_parse and raw_text:
        llm_fields = _extract_fields_with_local_llm(raw_text)
        if llm_fields is not None:
            for key in ("medication_name", "dosage", "instructions", "refills_remaining"):
                current_value = str(parsed.get(key) or "").strip()
                llm_value = llm_fields.get(key)
                if not current_value and isinstance(llm_value, str) and llm_value.strip():
                    parsed[key] = llm_value.strip()

            med_val = parsed.get("medication_name")
            med_str = med_val if isinstance(med_val, str) else None
            name_match = match_to_dict(med_str, threshold=85.0)
            parsed["medication_name_raw"] = name_match["raw_name"]
            parsed["medication_name"] = name_match["snapped_name"]
            parsed["medication_name_match_score"] = name_match["score"]
            parsed["medication_name_confidence"] = name_match["confidence"]
            parsed["medication_name_matched"] = name_match["matched"]
            parsed["medication_name_source"] = name_match.get("source")
            parsed["medication_name_rxcui"] = name_match.get("rxcui")

    flattened_first, _ = _warp_label_region(
        _apply_exif_orientation(image_paths[0], _load_image(image_paths[0]))
    )
    parsed["quality_gate"] = quality
    parsed["label_region"] = label_region
    parsed["label_preview_base64"] = _encode_preview_image(flattened_first)
    parsed["ocr_provider_chain"] = ocr_sources
    parsed["raw_text"] = raw_text
    if cloud_error:
        parsed["cloud_vision_error"] = cloud_error
    parsed["requires_human_review"] = (
        (not bool(quality.get("passed")))
        or not bool(parsed.get("medication_name_matched"))
        or not bool(parsed.get("medication_name"))
        or not bool(parsed.get("instructions"))
    )
    return parsed


def scan_prescription_label(
    image_path: Union[str, Path],
    device_ocr_text: Optional[str] = None,
    device_ocr_provider: Optional[str] = None,
) -> Dict[str, object]:
    return scan_prescription_label_multi_views([image_path], device_ocr_text, device_ocr_provider)
