import logging
import os
from pathlib import Path

from ultralytics import YOLO

logger = logging.getLogger(__name__)

_DEFAULT_MODEL_PATH = Path(__file__).resolve().parent.parent / "runs" / "pill_model" / "weights" / "best.pt"
_local_model = None


class PillDetectionUnavailable(RuntimeError):
    """Raised when the local pill detector checkpoint cannot be loaded."""


def _model_path() -> Path:
    configured = os.getenv("PILL_DETECTION_MODEL_PATH", "").strip()
    return Path(configured).expanduser() if configured else _DEFAULT_MODEL_PATH


def _get_model():
    global _local_model
    if _local_model is None:
        model_path = _model_path()
        if not model_path.is_file():
            raise PillDetectionUnavailable(
                f"Pill detector weights not found at {model_path}; set PILL_DETECTION_MODEL_PATH"
            )
        logger.info("Loading pill detector from %s", model_path)
        _local_model = YOLO(str(model_path))
    return _local_model


def preload() -> None:
    _get_model()


def _iter_predictions(res):
    if isinstance(res, list):
        res = res[0]
    if hasattr(res, "boxes") and res.boxes is not None:
        return res.boxes
    return []


def _confidence_of(p) -> float:
    return float(p.conf[0])


def _min_confidence() -> float:
    try:
        return float(os.getenv("PILL_SEGMENTATION_MIN_CONFIDENCE", "0.5"))
    except ValueError:
        return 0.5


def segment_and_crop_pills(image_bytes: bytes) -> list[bytes]:
    import cv2
    import numpy as np

    np_arr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Invalid image")
    model = _get_model()

    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    height, width = img_rgb.shape[:2]
    threshold = _min_confidence()

    crops = []
    for p in _iter_predictions(model(img_rgb)):
        if _confidence_of(p) < threshold:
            continue
        x1, y1, x2, y2 = (int(v) for v in p.xyxy[0].tolist())
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(width, x2), min(height, y2)
        if x2 <= x1 or y2 <= y1:
            continue
        crop_img = img_rgb[y1:y2, x1:x2]
        is_success, buffer = cv2.imencode(".jpg", cv2.cvtColor(crop_img, cv2.COLOR_RGB2BGR))
        if is_success:
            crops.append(buffer.tobytes())

    return crops
