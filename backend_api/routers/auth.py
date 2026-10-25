import os

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr
from sqlalchemy.ext.asyncio import AsyncSession

from backend_api.database import get_db
from backend_api.services.user_service import get_user_by_email, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class LoginUser(BaseModel):
    id: int
    email: EmailStr
    full_name: str


class LoginResponse(BaseModel):
    user: LoginUser


@router.post("/login", response_model=LoginResponse, status_code=status.HTTP_200_OK)
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)) -> LoginResponse:
    user = await get_user_by_email(db, payload.email.lower())
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")

    passwordless_enabled = os.getenv("ALLOW_PASSWORDLESS_LOGIN", "false").lower() in {
        "1",
        "true",
        "yes",
        "y",
    }
    password_matches = verify_password(payload.password, user.password_hash)
    if not password_matches and not (passwordless_enabled and not payload.password.strip()):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")

    return LoginResponse(
        user=LoginUser(
            id=user.id,
            email=user.email,
            full_name=user.full_name,
        )
    )
