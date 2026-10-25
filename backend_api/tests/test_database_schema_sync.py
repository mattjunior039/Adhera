import asyncio
import unittest

import backend_api.models  # noqa: F401  - register every table on Base.metadata
from backend_api.database import Base, _add_missing_nullable_columns
from sqlalchemy import inspect, text
from sqlalchemy.ext.asyncio import create_async_engine


class SchemaSyncTests(unittest.TestCase):
    def test_existing_table_gains_new_nullable_columns_without_losing_rows(self) -> None:
        async def run() -> None:
            engine = create_async_engine("sqlite+aiosqlite:///:memory:")
            async with engine.begin() as connection:
                await connection.run_sync(Base.metadata.create_all)
                # Simulate a database created before state/quality_score existed.
                await connection.execute(text("DROP TABLE inference_results"))
                await connection.execute(
                    text(
                        "CREATE TABLE inference_results ("
                        "id INTEGER PRIMARY KEY, photo_event_id INTEGER NOT NULL, "
                        "baseline_event_id INTEGER NOT NULL, compartment_index INTEGER NOT NULL, "
                        "is_changed BOOLEAN NOT NULL, confidence FLOAT NOT NULL)"
                    )
                )
                await connection.execute(text("INSERT INTO inference_results VALUES (1, 1, 1, 0, 1, 0.9)"))

                added = await connection.run_sync(_add_missing_nullable_columns)
                self.assertEqual(
                    sorted(added),
                    ["inference_results.quality_score", "inference_results.state"],
                )

                columns = await connection.run_sync(
                    lambda sync: {c["name"] for c in inspect(sync).get_columns("inference_results")}
                )
                self.assertTrue({"state", "quality_score"} <= columns)
                rows = (await connection.execute(text("SELECT id, state FROM inference_results"))).all()
                self.assertEqual(rows, [(1, None)])

                self.assertEqual(await connection.run_sync(_add_missing_nullable_columns), [])
            await engine.dispose()

        asyncio.run(run())


if __name__ == "__main__":
    unittest.main()
