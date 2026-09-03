import sys
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

try:
    from backend_api.database import init_db
    from backend_api.routers.adherence import router as adherence_router
    from backend_api.routers.auth import router as auth_router
    from backend_api.routers.medications import router as medications_router
    from backend_api.routers.photo_events import router as photo_events_router
    from backend_api.routers.schedules import router as schedules_router
    from backend_api.routers.users import router as users_router
    # Import models so init_db creates all tables including new ones
    import backend_api.models.dose_outcome  # noqa: F401
except ImportError:  # pragma: no cover - script execution fallback
    from database import init_db
    from routers.adherence import router as adherence_router
    from routers.auth import router as auth_router
    from routers.medications import router as medications_router
    from routers.photo_events import router as photo_events_router
    from routers.schedules import router as schedules_router
    from routers.users import router as users_router
    import models.dose_outcome  # noqa: F401

app = FastAPI(
    title="Pillbox Medication Management API",
    version="1.0.0",
    description="Medication tracking backend that records users, medications, schedules, and photo-based interactions.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup_event() -> None:
    await init_db()


@app.get("/")
async def root() -> dict[str, str]:
    return {"app": "Pillbox API", "status": "ok"}


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(auth_router)
app.include_router(users_router)
app.include_router(medications_router)
app.include_router(schedules_router)
app.include_router(photo_events_router)
app.include_router(adherence_router)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
