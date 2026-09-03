from typing import Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class UserBase(BaseModel):
    email: EmailStr
    full_name: str = Field(..., min_length=1, max_length=255)
    phone: Optional[str] = Field(default=None, max_length=50)


class UserCreate(UserBase):
    password: str = Field(..., min_length=8, max_length=255)


class UserResponse(UserBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
