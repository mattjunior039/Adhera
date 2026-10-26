from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from backend_api.database import get_db
from backend_api.schemas.compartment_inventory import (
    CompartmentInventoryResponse,
    CompartmentInventoryUpdate,
)
from backend_api.services.compartment_inventory_service import (
    get_inventory,
    initialize_test_inventory,
    update_inventory_slot,
)

router = APIRouter(prefix="/adhera", tags=["adhera-inventory"])


def _response(slot) -> CompartmentInventoryResponse:
    return CompartmentInventoryResponse(
        id=slot.id,
        user_id=slot.user_id,
        day_of_week=slot.day_of_week,
        period=slot.period,
        medication_id=slot.medication_id,
        medication_name=slot.medication.name,
        pill_count=slot.pill_count,
        updated_at=slot.updated_at,
    )


@router.get("/{user_id}/inventory", response_model=list[CompartmentInventoryResponse])
async def get_adhera_inventory(
    user_id: int,
    db: AsyncSession = Depends(get_db),
) -> list[CompartmentInventoryResponse]:
    return [_response(slot) for slot in await get_inventory(db, user_id)]


@router.post(
    "/{user_id}/initialize-test-inventory",
    response_model=list[CompartmentInventoryResponse],
)
async def initialize_adhera_inventory(
    user_id: int,
    db: AsyncSession = Depends(get_db),
) -> list[CompartmentInventoryResponse]:
    try:
        slots = await initialize_test_inventory(db, user_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    return [_response(slot) for slot in slots]


@router.put(
    "/{user_id}/inventory/{slot_id}",
    response_model=CompartmentInventoryResponse,
)
async def update_adhera_inventory(
    user_id: int,
    slot_id: int,
    payload: CompartmentInventoryUpdate,
    db: AsyncSession = Depends(get_db),
) -> CompartmentInventoryResponse:
    try:
        slot = await update_inventory_slot(
            db,
            user_id,
            slot_id,
            payload.medication_id,
            payload.pill_count,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    if slot is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Compartment not found")
    await db.commit()
    return _response(slot)
