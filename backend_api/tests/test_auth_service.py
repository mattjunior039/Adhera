import asyncio
import os
import unittest
from unittest.mock import patch

from backend_api.database import Base
from backend_api.models.user import User
from backend_api.routers.auth import LoginRequest, login
from backend_api.schemas.user import UserCreate
from backend_api.services.user_service import create_user
from fastapi import HTTPException
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine


class AuthFlowTests(unittest.TestCase):
    def test_valid_credentials_succeed_and_invalid_credentials_are_rejected(self) -> None:
        async def run() -> None:
            engine = create_async_engine("sqlite+aiosqlite:///:memory:")
            async with engine.begin() as connection:
                await connection.run_sync(
                    lambda sync: Base.metadata.create_all(sync, tables=[User.__table__])
                )
            sessions = async_sessionmaker(engine, expire_on_commit=False)
            async with sessions() as db:
                user = await create_user(
                    db,
                    UserCreate(
                        email="patient@example.com",
                        full_name="Test Patient",
                        password="Correct horse battery staple",
                    ),
                )
                result = await login(
                    LoginRequest(email=user.email, password="Correct horse battery staple"),
                    db,
                )
                self.assertEqual(result.user.id, user.id)

                with patch.dict(os.environ, {"ALLOW_PASSWORDLESS_LOGIN": "true"}):
                    passwordless = await login(LoginRequest(email=user.email, password=""), db)
                self.assertEqual(passwordless.user.id, user.id)

                with patch.dict(os.environ, {"ALLOW_PASSWORDLESS_LOGIN": "false"}):
                    with self.assertRaises(HTTPException) as blank_password_disabled:
                        await login(LoginRequest(email=user.email, password=""), db)
                self.assertEqual(blank_password_disabled.exception.status_code, 401)

                with self.assertRaises(HTTPException) as wrong_password:
                    await login(LoginRequest(email=user.email, password="wrong password"), db)
                self.assertEqual(wrong_password.exception.status_code, 401)

                with self.assertRaises(HTTPException) as unknown_user:
                    await login(
                        LoginRequest(email="nobody@example.com", password="anything valid"),
                        db,
                    )
                self.assertEqual(unknown_user.exception.status_code, 401)
            await engine.dispose()

        asyncio.run(run())


if __name__ == "__main__":
    unittest.main()
