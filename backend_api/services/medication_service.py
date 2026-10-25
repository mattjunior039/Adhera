from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend_api.models.medication import Medication
from backend_api.schemas.medication import MedicationCreate, MedicationUpdate


async def create_medication(db: AsyncSession, medication_in: MedicationCreate) -> Medication:
    medication = Medication(**medication_in.model_dump())
    db.add(medication)
    await db.commit()
    await db.refresh(medication)
    return medication


async def update_medication(
    db: AsyncSession, medication_id: int, data: MedicationUpdate
) -> Optional[Medication]:
    medication = await db.get(Medication, medication_id)
    if medication is None:
        return None
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(medication, field, value)
    await db.commit()
    await db.refresh(medication)
    return medication


async def get_user_medications(db: AsyncSession, user_id: int) -> list[Medication]:
    result = await db.execute(select(Medication).where(Medication.user_id == user_id).order_by(Medication.id))
    return list(result.scalars().all())
