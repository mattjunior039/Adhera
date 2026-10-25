from typing import Optional

from fastapi import APIRouter, File, Form, HTTPException, UploadFile, status

from backend_api.services.pill_identity import (
    EMBEDDING_DIMENSIONS,
    PillEmbeddingUnavailable,
    generate_pill_signature,
)
from backend_api.services.pill_reference_service import identify_reference_image

router = APIRouter(prefix="", tags=["pill-analysis"])


@router.post("/pills/identify")
async def identify_pill(
    file: UploadFile = File(...),
) -> dict[str, object]:
    """Match an image to the nearest bundled medication reference photo."""
    content = await file.read()
    if not content:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="The uploaded image was empty")

    try:
        return identify_reference_image(content)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except PillEmbeddingUnavailable as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc


@router.post("/pills/analyze")
async def analyze_pills(
    file: UploadFile = File(...),
    user_id: Optional[int] = Form(default=None),
) -> dict:
    """Segment every pill in an uploaded photo and return one signature per pill."""
    content = await file.read()
    if not content:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="The uploaded image was empty")

    try:
        from backend_api.services.pill_vision import (
            PillDetectionUnavailable,
            segment_and_crop_pills,
        )
    except ImportError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Pill detection dependencies are not installed on this backend",
        ) from exc

    try:
        crops = segment_and_crop_pills(content)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except PillDetectionUnavailable as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    embeddings: list[list[float]] = []
    try:
        for crop in crops:
            embeddings.append(generate_pill_signature(crop))
    except PillEmbeddingUnavailable as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc

    return {
        "user_id": user_id,
        "pill_count": len(embeddings),
        "embedding_dimensions": EMBEDDING_DIMENSIONS,
        "embeddings": embeddings,
    }
