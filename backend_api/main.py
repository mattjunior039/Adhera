"""Adhera API entry point.

Run from the repository root with ``uvicorn backend_api.main:app`` or from this
folder with ``uvicorn main:app``.
"""

import logging
import os
import sys
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware

if __package__ in (None, ""):
    # Allow ``uvicorn main:app`` from inside backend_api/.
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from backend_api.database import init_db
from backend_api.routers import (
    adhera,
    adherence,
    auth,
    dose_verification,
    medications,
    photo_events,
    pill_analysis,
    schedules,
    users,
)

logger = logging.getLogger(__name__)


async def _preload_pill_models() -> None:
    try:
        from backend_api.services import pill_identity, pill_vision
    except ImportError as exc:
        logger.warning("Pill model preload skipped because dependencies are unavailable: %s", exc)
        return

    # Never let a missing checkpoint or absent ML extra stop the API from booting.
    for module in (pill_vision, pill_identity):
        try:
            await run_in_threadpool(module.preload)
        except Exception as exc:  # noqa: BLE001
            logger.warning("Pill model preload skipped for %s: %s", module.__name__, exc)


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    await init_db()
    # Off by default: models otherwise load lazily on first use.
    if os.getenv("PRELOAD_PILL_MODELS", "false").lower() in {"1", "true", "yes", "y"}:
        await _preload_pill_models()
    yield


app = FastAPI(
    title="Adhera Medication Management API",
    version="1.0.0",
    description=(
        "Medication adherence backend: users, medications, schedules, prescription "
        "label scanning, Adhera inventory, and human-reviewed photo/video verification."
    ),
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

for module in (
    auth,
    users,
    medications,
    schedules,
    photo_events,
    adherence,
    dose_verification,
    pill_analysis,
    adhera,
):
    app.include_router(module.router)


@app.get("/")
async def root() -> dict[str, str]:
    return {"app": "Adhera API", "status": "ok"}


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
