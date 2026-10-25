import logging
from collections.abc import AsyncGenerator

from sqlalchemy import inspect, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from backend_api.config import get_database_url

logger = logging.getLogger(__name__)


class Base(DeclarativeBase):
    pass


database_url = get_database_url()
engine = create_async_engine(
    database_url,
    echo=False,
    future=True,
    pool_pre_ping=True,
    connect_args={"check_same_thread": False} if database_url.startswith("sqlite") else {},
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)


def _add_missing_nullable_columns(connection) -> list[str]:
    """Add nullable columns that exist on models but not in existing tables.

    ``create_all`` only creates missing tables, so databases created by an
    earlier version silently lack newer columns. Only nullable columns without
    server defaults are added; anything else needs a deliberate migration.
    """
    inspector = inspect(connection)
    existing_tables = set(inspector.get_table_names())
    preparer = connection.dialect.identifier_preparer
    added: list[str] = []
    for table in Base.metadata.sorted_tables:
        if table.name not in existing_tables:
            continue
        present = {column["name"] for column in inspector.get_columns(table.name)}
        for column in table.columns:
            if column.name in present:
                continue
            if not column.nullable or column.server_default is not None:
                logger.warning(
                    "Column %s.%s is missing and cannot be added automatically; apply a migration.",
                    table.name,
                    column.name,
                )
                continue
            column_type = column.type.compile(dialect=connection.dialect)
            connection.execute(
                text(
                    f"ALTER TABLE {preparer.quote(table.name)} "
                    f"ADD COLUMN {preparer.quote(column.name)} {column_type}"
                )
            )
            added.append(f"{table.name}.{column.name}")
    if added:
        logger.info("Added missing nullable columns: %s", ", ".join(added))
    return added


async def init_db() -> None:
    import backend_api.models  # noqa: F401  - register every table on Base.metadata

    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
        await connection.run_sync(_add_missing_nullable_columns)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        yield session
