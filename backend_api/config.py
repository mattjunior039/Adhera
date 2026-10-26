import os
from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()


@lru_cache(maxsize=1)
def get_database_url() -> str:
    """Return the async database URL.

    Defaults to SQLite for local development so the project runs without a
    separate Postgres instance. Postgres remains available via DATABASE_URL or
    POSTGRES_* environment variables when a managed database is configured.
    """
    database_url = os.getenv("DATABASE_URL")
    if database_url:
        return database_url

    if os.getenv("USE_SQLITE", "true").lower() in {"1", "true", "yes", "y"}:
        sqlite_path = Path(__file__).resolve().parent / "adhera.db"
        return f"sqlite+aiosqlite:///{sqlite_path}"

    user = os.getenv("POSTGRES_USER", "adhera_user")
    password = os.getenv("POSTGRES_PASSWORD", "adhera_password")
    host = os.getenv("POSTGRES_HOST", "localhost")
    port = os.getenv("POSTGRES_PORT", "5432")
    db_name = os.getenv("POSTGRES_DB", "adhera")
    return f"postgresql+asyncpg://{user}:{password}@{host}:{port}/{db_name}"
