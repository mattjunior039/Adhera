"""OCR pipeline for prescription label scanning using Gemini LLM.

Pipeline goals:
- quality control gate before OCR
- automatic label-region flattening and crop before AI extraction
- Gemini structured output (JSON) extraction via google-genai
"""

from __future__ import annotations

import base64
import os
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


def _normalize_for_cloud_ocr(img: np.ndarray) -> np.ndarray:
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


from pydantic import BaseModel, Field


class PrescriptionParseResult(BaseModel):
    medication_name: str = Field(default="")
    dosage: str = Field(default="")
    instructions: str = Field(default="")
    medication_name_raw: str = Field(default="")
    medication_name_confidence: str = Field(default="high")
    medication_name_matched: bool = Field(default=False)
    medication_name_match_score: float = Field(default=0.0)
    medication_name_source: str = Field(default="gemini")
    medication_name_rxcui: Optional[str] = Field(default=None)
    refills_remaining: str = Field(default="")
    prescribed_by: str = Field(default="")
    pharmacy: str = Field(default="")
    requires_human_review: bool = Field(default=False)


def _call_gemini_ocr(images: list[np.ndarray], device_text: str = "") -> Dict[str, object]:
    try:
        import PIL.Image
        from google import genai
        from google.genai import types

        api_key = os.getenv("GEMINI_API_KEY", os.getenv("GOOGLE_API_KEY", ""))
        if not api_key:
            # Fallback if no API key is provided
            return PrescriptionParseResult(requires_human_review=True, raw_text=device_text).model_dump()

        client = genai.Client(api_key=api_key)

        contents = []
        for img in images:
            rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            pil_img = PIL.Image.fromarray(rgb)
            contents.append(pil_img)

        prompt = (
            "Extract prescription details from these label images. "
            f"Here is a device-provided OCR hint if helpful: {device_text}. "
            "Ensure you extract the medication name, dosage, instructions (SIG), refills, pharmacy, and prescriber."
        )
        contents.append(prompt)

        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=contents,
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=PrescriptionParseResult,
                temperature=0.0,
            ),
        )
        if response.parsed:
            return response.parsed.model_dump()
        else:
            return PrescriptionParseResult(requires_human_review=True, raw_text=device_text).model_dump()

    except Exception as e:
        return PrescriptionParseResult(requires_human_review=True, raw_text=str(e)).model_dump()


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
        normalized = _normalize_for_cloud_ocr(cropped)
        normalized_views.append(normalized)

    parsed_dict = _call_gemini_ocr(normalized_views, device_ocr_text or "")

    # Generate preview from the first flattened frame
    flattened, _ = _warp_label_region(_apply_exif_orientation(image_paths[0], _load_image(image_paths[0])))
    parsed_dict["label_preview_base64"] = _encode_preview_image(flattened)
    parsed_dict["raw_text"] = device_ocr_text or ""
    parsed_dict["ocr_provider_chain"] = [device_ocr_provider or "device_hint", "gemini-2.5-flash"]
    parsed_dict["quality_gate"] = _quality_gate(normalized_views[0]) if normalized_views else {}

    return parsed_dict


def scan_prescription_label(
    image_path: Union[str, Path],
    device_ocr_text: Optional[str] = None,
    device_ocr_provider: Optional[str] = None,
) -> Dict[str, object]:
    return scan_prescription_label_multi_views([image_path], device_ocr_text, device_ocr_provider)
