from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from backend_api.database import get_db
from backend_api.models.photo_event import PhotoEvent
from backend_api.schemas.inference_result import (
    AnalyzePhotoRequest,
    InferenceResultResponse,
)
from backend_api.schemas.photo_event import PhotoEventCreate, PhotoEventResponse
from backend_api.services.inference_service import analyze_photo_event
from backend_api.services.photo_event_service import (
    create_photo_event,
    get_user_photo_events,
)

router = APIRouter(prefix="", tags=["photo-events"])

UPLOAD_DIR = Path(__file__).resolve().parent.parent / "uploads"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


@router.post("/photo-events", response_model=PhotoEventResponse, status_code=status.HTTP_201_CREATED)
async def log_photo_event(event: PhotoEventCreate, db: AsyncSession = Depends(get_db)) -> PhotoEventResponse:
    try:
        created = await create_photo_event(db, event)
        return PhotoEventResponse.model_validate(created)
    except Exception as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/images/upload")
async def upload_photo(
    user_id: int = Form(...),
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
):
    if not file.filename:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="A file name is required")

    try:
        file_bytes = await file.read()
        extension = Path(file.filename).suffix or ".jpg"
        unique_name = f"{uuid4()}_{int(datetime.now(timezone.utc).timestamp())}{extension}"
        save_path = UPLOAD_DIR / unique_name
        save_path.write_bytes(file_bytes)
    except OSError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to write image file: {exc}"
        ) from exc

    try:
        photo_event = PhotoEvent(
            user_id=user_id,
            event_type="adhera_capture",
            photo_path=str(save_path),
            event_time=datetime.now(timezone.utc),
            notes="Uploaded from mobile app",
        )
        db.add(photo_event)
        await db.commit()
        await db.refresh(photo_event)
    except Exception as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=f"Failed to save photo event: {exc}"
        ) from exc

    return {
        "photo_event_id": photo_event.id,
        "message": "Image uploaded successfully",
    }


@router.get("/photo-events/{user_id}", response_model=list[PhotoEventResponse])
async def get_photo_events(user_id: int, db: AsyncSession = Depends(get_db)) -> list[PhotoEventResponse]:
    events = await get_user_photo_events(db, user_id)
    return [PhotoEventResponse.model_validate(item) for item in events]


@router.post("/analyze/{photo_event_id}", response_model=list[InferenceResultResponse])
async def analyze_photo_event_route(
    photo_event_id: int,
    payload: AnalyzePhotoRequest,
    db: AsyncSession = Depends(get_db),
) -> list[InferenceResultResponse]:
    try:
        results = await analyze_photo_event(db, photo_event_id, payload.baseline_event_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except Exception as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Analysis failed: {exc}"
        ) from exc

    return [InferenceResultResponse.model_validate(result) for result in results]


@router.post("/prescriptions/scan")
async def scan_prescription(
    user_id: int = Form(...),
    files: list[UploadFile] = File(...),
    device_ocr_text: Optional[str] = Form(default=None),
    device_ocr_provider: Optional[str] = Form(default=None),
) -> dict:
    """Upload multi-view prescription keyframes and return fused medication details."""
    if not files:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No images provided.")

    temporary_paths: list[Path] = []
    try:
        from backend_api.services.ocr_service import scan_prescription_label_multi_views

        for index, upload in enumerate(files):
            content = await upload.read()
            if not content:
                continue
            extension = Path(upload.filename or ".jpg").suffix or ".jpg"
            path = UPLOAD_DIR / f"scan_{uuid4().hex}_view_{index + 1}{extension}"
            path.write_bytes(content)
            temporary_paths.append(path)

        if not temporary_paths:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No readable image files were provided.",
            )

        result = scan_prescription_label_multi_views(
            temporary_paths,
            device_ocr_text=device_ocr_text,
            device_ocr_provider=device_ocr_provider,
        )
        label_region = result.get("label_region")
        if not isinstance(label_region, dict):
            label_region = {}
            result["label_region"] = label_region
        label_region["views_received"] = len(files)
    except RuntimeError as exc:
        raise HTTPException(
            status_code=503,
            detail=f"OCR service unavailable: {exc}",
        ) from exc
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    finally:
        for path in temporary_paths:
            path.unlink(missing_ok=True)

    return result


@router.post("/prescriptions/prepare")
async def prepare_prescription_label(
    user_id: int = Form(...),
    file: UploadFile = File(...),
) -> dict:
    """Return a flattened label crop before OCR is run.

    The mobile client uses this step to submit the rectified label image to the OCR
    endpoint instead of the original curved bottle photo.
    """
    file_bytes = await file.read()
    extension = Path(file.filename or "label").suffix or ".jpg"
    tmp_path = UPLOAD_DIR / f"prepare_{uuid4().hex}{extension}"
    tmp_path.write_bytes(file_bytes)

    try:
        import cv2

        from backend_api.services.ocr_service import (
            _encode_preview_image,
            _warp_label_region,
        )

        source = cv2.imread(str(tmp_path))
        if source is None:
            raise ValueError("Cannot open uploaded image")
        flattened, label_region = _warp_label_region(source)
        preview_base64 = _encode_preview_image(flattened)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Label preparation failed: {exc}"
        ) from exc
    finally:
        tmp_path.unlink(missing_ok=True)

    return {
        "user_id": user_id,
        "label_preview_base64": preview_base64,
        "label_region": label_region,
    }


@router.post("/prescriptions/prepare-multi")
async def prepare_prescription_label_multi(
    user_id: int = Form(...),
    files: list[UploadFile] = File(...),
) -> dict:
    """Return a single flattened label crop composed from multiple frames."""
    if not files:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="At least one image file is required"
        )

    try:
        import cv2
        import numpy as np

        from backend_api.services.ocr_service import (
            _encode_preview_image,
            compose_flattened_label_from_images,
        )

        images = []
        for upload in files:
            content = await upload.read()
            if not content:
                continue
            array = np.frombuffer(content, dtype=np.uint8)
            decoded = cv2.imdecode(array, cv2.IMREAD_COLOR)
            if decoded is not None:
                images.append(decoded)

        if not images:
            raise ValueError("Could not decode any uploaded images")

        composite, label_region = compose_flattened_label_from_images(images)
        preview_base64 = _encode_preview_image(composite)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Label composition failed: {exc}"
        ) from exc

    return {
        "user_id": user_id,
        "label_preview_base64": preview_base64,
        "label_region": label_region,
    }
