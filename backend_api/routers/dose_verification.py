import json
import logging
import math
from collections.abc import Mapping
from pathlib import Path
from typing import Optional
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool

from backend_api.database import get_db
from backend_api.models.compartment_inventory import CompartmentInventory
from backend_api.models.dose_verification_event import DoseVerificationEvent
from backend_api.models.medication import Medication
from backend_api.models.schedule import Schedule
from backend_api.models.user import User
from backend_api.schemas.adhera_orientation import (
    AdheraOrientationResponse,
    AdheraOrientationUpdate,
)
from backend_api.schemas.dose_verification_event import DoseVerificationEventResponse
from backend_api.services import adhera_orientation_service as orientation_service
from backend_api.services.video_verification_service import (
    VideoAnalysisBusy,
    VideoModelUnavailable,
    analyze_dose_removal_video,
)

router = APIRouter(tags=["dose-verification"])
logger = logging.getLogger(__name__)
UPLOAD_DIR = Path(__file__).resolve().parent.parent / "uploads"
MAX_UPLOAD_BYTES = 50 * 1024 * 1024


def _response(event: DoseVerificationEvent, evidence: Mapping[str, object]) -> DoseVerificationEventResponse:
    values = DoseVerificationEventResponse.model_validate(event).model_dump()
    return DoseVerificationEventResponse.model_validate(
        {
            **values,
            "recognized_medication": evidence.get("medication_class"),
            "inventory_updated": False,
            "reason": evidence.get("reason"),
            "prototype": evidence.get("prototype"),
            "evidence_scope": evidence.get("evidence_scope"),
            "analysis_mode": evidence.get("mode"),
            "destination_label": f"{evidence['destination_day']}_PM"
            if evidence.get("destination_day")
            else None,
            "removed_count": evidence.get("removed_count"),
            "transferred_count": evidence.get("transferred_count"),
            "model_provenance": evidence.get("model_provenance", {}),
        }
    )


@router.post("/dose-verification/analyze-video", response_model=DoseVerificationEventResponse)
async def analyze_dose_verification_video(
    user_id: int = Form(...),
    medication_id: Optional[int] = Form(default=None),
    schedule_id: Optional[int] = Form(default=None),
    compartment_id: Optional[int] = Form(default=None),
    before_start: Optional[float] = Form(default=None),
    before_end: Optional[float] = Form(default=None),
    after_start: Optional[float] = Form(default=None),
    after_end: Optional[float] = Form(default=None),
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
) -> DoseVerificationEventResponse:
    """Review-only official blue PM row, SUN to SAT left-to-right; never changes inventory."""
    if await db.get(User, user_id) is None:
        raise HTTPException(404, "User not found")
    expected_label = None
    for model, record_id, name in (
        (Medication, medication_id, "Medication"),
        (Schedule, schedule_id, "Schedule"),
        (CompartmentInventory, compartment_id, "Compartment"),
    ):
        if record_id is None:
            continue
        record = await db.get(model, record_id)
        if record is None or record.user_id != user_id:
            raise HTTPException(404, f"{name} not found")
        if isinstance(record, Schedule):
            period = "AM" if record.time_of_day.hour < 12 else "PM"
            expected_label = f"{record.day_of_week[:3].upper()}_{period}"
        elif isinstance(record, CompartmentInventory):
            expected_label = f"{record.day_of_week[:3].upper()}_{record.period}"
    times = (before_start, before_end, after_start, after_end)
    windows = None
    if any(value is not None for value in times):
        if before_start is None or before_end is None or after_start is None or after_end is None:
            raise HTTPException(400, "Provide all four finite before/after timestamps, or none")
        if not all(math.isfinite(value) for value in (before_start, before_end, after_start, after_end)):
            raise HTTPException(400, "Timestamps must be finite")
        if not (0 <= before_start < before_end < after_start < after_end <= 120):
            raise HTTPException(400, "Intervals must be ordered, disjoint and within 120 seconds")
        windows = ((before_start, before_end), (after_start, after_end))

    save_path = UPLOAD_DIR / f"{uuid4()}.mp4"
    evidence_path = save_path.with_suffix(".analysis.json")
    persisted = False
    try:
        UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
        size = 0
        with save_path.open("xb") as output:
            while chunk := await file.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_UPLOAD_BYTES:
                    raise HTTPException(413, "Video upload exceeds 50 MiB")
                await run_in_threadpool(output.write, chunk)
        if size == 0:
            raise HTTPException(400, "The uploaded video was empty")
        # Expected labels are metadata only; they never enter model inference or orientation.
        result = await run_in_threadpool(analyze_dose_removal_video, save_path, windows=windows)
        await run_in_threadpool(
            evidence_path.write_text,
            json.dumps(result, allow_nan=False),
            encoding="utf-8",
        )
        event = DoseVerificationEvent(
            user_id=user_id,
            medication_id=medication_id,
            schedule_id=schedule_id,
            video_path=str(save_path),
            compartment_index=result["compartment_index"],
            assumed_label=result["assumed_label"],
            expected_label=expected_label,
            am_row=None,
            period_confident=True,
            orientation_calibrated=False,
            wrong_slot=bool(
                expected_label and result["assumed_label"] and expected_label != result["assumed_label"]
            ),
            pre_count=result["pre_count"],
            post_count=result["post_count"],
            event_type=result["event_type"],
            confidence=result["confidence"],
            requires_review=True,
            frames_sampled=result["frames_sampled"],
            frames_accepted=result["frames_accepted"],
        )
        db.add(event)
        await db.commit()
        persisted = True
        await db.refresh(event)
        return _response(event, result)
    except VideoAnalysisBusy as exc:
        raise HTTPException(503, str(exc), headers={"Retry-After": "5"}) from exc
    except VideoModelUnavailable as exc:
        logger.warning("Video model unavailable: %s", exc)
        raise HTTPException(503, str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    except (OSError, SQLAlchemyError) as exc:
        await db.rollback()
        logger.exception("Unable to persist video analysis")
        raise HTTPException(500, "Unable to save video analysis") from exc
    finally:
        await file.close()
        if not persisted:
            evidence_path.unlink(missing_ok=True)
            save_path.unlink(missing_ok=True)


@router.get("/dose-verification/{user_id}", response_model=list[DoseVerificationEventResponse])
async def get_dose_verification_events(user_id: int, db: AsyncSession = Depends(get_db)):
    rows = (
        (
            await db.execute(
                select(DoseVerificationEvent)
                .where(DoseVerificationEvent.user_id == user_id)
                .order_by(DoseVerificationEvent.created_at.desc())
            )
        )
        .scalars()
        .all()
    )
    responses = []
    for event in rows:
        path = Path(event.video_path).with_suffix(".analysis.json")
        if path.is_file():
            try:
                evidence = json.loads(await run_in_threadpool(path.read_text, encoding="utf-8"))
                if not isinstance(evidence, dict):
                    raise ValueError("Video evidence must be a JSON object")
            except (OSError, ValueError) as exc:
                logger.exception("Unreadable video evidence for event %s", event.id)
                raise HTTPException(500, "Saved video evidence is unreadable") from exc
        elif event.event_type.startswith("CANDIDATE_"):
            raise HTTPException(500, f"Saved video evidence missing for event {event.id}")
        else:
            evidence = {}
        responses.append(_response(event, evidence))
    return responses


@router.get("/adhera-orientation/{user_id}", response_model=Optional[AdheraOrientationResponse])
async def get_adhera_orientation(user_id: int, db: AsyncSession = Depends(get_db)):
    profile = await orientation_service.get_orientation_profile(db, user_id)
    return AdheraOrientationResponse.model_validate(profile) if profile else None


@router.put("/adhera-orientation/{user_id}", response_model=AdheraOrientationResponse)
async def set_adhera_orientation(
    user_id: int,
    payload: AdheraOrientationUpdate,
    db: AsyncSession = Depends(get_db),
):
    """Legacy orientation preferences; official blue PM videos have fixed orientation."""
    try:
        profile = await orientation_service.set_orientation_profile(db, user_id, payload.column_order)
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    return AdheraOrientationResponse.model_validate(profile)
