from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

try:
    from backend_api.database import get_db
    from backend_api.schemas.user import UserCreate, UserResponse
    from backend_api.services.user_service import create_user, get_user_by_email, get_user_by_id
except ImportError:  # pragma: no cover - script execution fallback
    from database import get_db
    from schemas.user import UserCreate, UserResponse
    from services.user_service import create_user, get_user_by_email, get_user_by_id

router = APIRouter(prefix="/users", tags=["users"])


@router.post("", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_new_user(user: UserCreate, db: AsyncSession = Depends(get_db)) -> UserResponse:
    try:
        existing = await get_user_by_email(db, user.email.lower())
        if existing is not None:
            raise ValueError("A user with that email already exists")
        created = await create_user(db, user)
        return UserResponse.model_validate(created)
    except ValueError as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except Exception as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/{user_id}", response_model=UserResponse)
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)) -> UserResponse:
    user = await get_user_by_id(db, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return UserResponse.model_validate(user)


@router.get("/by-email/{email}", response_model=UserResponse)
async def get_user_by_email_route(email: str, db: AsyncSession = Depends(get_db)) -> UserResponse:
    user = await get_user_by_email(db, email.lower())
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return UserResponse.model_validate(user)
