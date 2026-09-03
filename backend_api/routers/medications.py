from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

try:
    from backend_api.database import get_db
    from backend_api.schemas.medication import MedicationCreate, MedicationResponse, MedicationUpdate
    from backend_api.services.medication_service import create_medication, get_user_medications, update_medication
except ImportError:  # pragma: no cover - script execution fallback
    from database import get_db
    from schemas.medication import MedicationCreate, MedicationResponse, MedicationUpdate
    from services.medication_service import create_medication, get_user_medications, update_medication

router = APIRouter(prefix="", tags=["medications"])


@router.post("/medications", response_model=MedicationResponse, status_code=status.HTTP_201_CREATED)
async def add_medication(medication: MedicationCreate, db: AsyncSession = Depends(get_db)) -> MedicationResponse:
    try:
        created = await create_medication(db, medication)
        return MedicationResponse.model_validate(created)
    except Exception as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.put("/medications/{medication_id}", response_model=MedicationResponse)
async def edit_medication(
    medication_id: int, medication: MedicationUpdate, db: AsyncSession = Depends(get_db)
) -> MedicationResponse:
    updated = await update_medication(db, medication_id, medication)
    if updated is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Medication not found")
    return MedicationResponse.model_validate(updated)


@router.get("/medications/{user_id}", response_model=list[MedicationResponse])
async def list_medications(user_id: int, db: AsyncSession = Depends(get_db)) -> list[MedicationResponse]:
    medications = await get_user_medications(db, user_id)
    return [MedicationResponse.model_validate(item) for item in medications]
