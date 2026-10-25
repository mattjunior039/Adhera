# Deployment

This guide covers running the backend with Docker and PostgreSQL, the
configuration options, and what to change before a real deployment. For local
development with SQLite, see the [root README](../README.md#getting-started).

## Docker Compose

`backend_api/docker-compose.yml` starts two containers:

| Service | Image | Host address |
| --- | --- | --- |
| `db` | PostgreSQL 15 | `127.0.0.1:5433` |
| `api` | Built from `backend_api/Dockerfile` (Python 3.11) | `http://127.0.0.1:8001` |

```bash
cd backend_api
cp .env.example .env
docker compose up --build
curl http://127.0.0.1:8001/health

# Create the demo account (adherasample@gmail.com / AdheraDemo2026)
docker compose exec api python -m backend_api.scripts.seed_sample_schedule
```

The API container is published on port 8001 so it never collides with a native
development server on port 8000. Point the app at it explicitly:

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8001
```

Compose also:

- sets `DATABASE_URL` to the `db` container,
- mounts `backend_api/runs/` at `/app/runs` so locally trained model checkpoints are available,
- mounts `services/`, `routers/`, and `main.py` so code changes apply without rebuilding the image,
- keeps downloaded model weights (DINOv2) on the `model_cache` volume.

## Configuration

All settings are environment variables. `backend_api/.env.example` lists every
one with comments. The most important are:

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` / `USE_SQLITE` / `POSTGRES_*` | Database selection. SQLite is the default; `DATABASE_URL` takes priority. |
| `RXNORM_LOOKUP_MODE` | `api`, `local`, or `both` (local file first, then the NIH RxNav API). Use `local` to make no external requests at all. |
| `PILL_EMBEDDING_DEVICE` | Torch device for DINOv2: `cpu`, `cuda`, or `mps`. |
| `OFFICIAL_PILL_CHECKPOINT`, `OFFICIAL_COMPARTMENT_CHECKPOINT`, `OFFICIAL_VIDEO_DEVICE` | Video verification models and device. |
| `PILL_DETECTION_MODEL_PATH` | Loose-pill detector used by `/pills/analyze`. |
| `PRELOAD_PILL_MODELS` | Load the pill models at start-up instead of on first use. |

If a model file is missing, its endpoint returns HTTP 503 with an explanation.
The rest of the API keeps working.

## Optional local RxNorm dataset

A local names file avoids depending on the RxNav API for every lookup.
`backend_api/datasets/rxnorm_names.sample.json` shows the format.

```bash
python -m backend_api.scripts.validate_rxnorm_local backend_api/datasets/rxnorm_names.json
```

Then set `RXNORM_LOCAL_PATH` to that file and `RXNORM_LOOKUP_MODE=both`.

## Tuning the label quality check

To tune the blur, exposure, contrast, and skew thresholds on your own label
photos:

```bash
python -m backend_api.scripts.tune_ocr_quality /path/to/label-photos
```

## Before a production deployment

- **HTTPS and CORS:** serve the API over HTTPS, and replace the wildcard CORS
  setting in `main.py` with your app's origins.
- **Request limits:** video uploads are capped at 50 MiB in code. Also enforce
  request-size limits at the proxy or ingress.
- **Storage:** keep `uploads/` on durable storage if you need to retain
  evidence. Each video's `.analysis.json` report should stay with its upload.
  Temporary prescription-scan files are deleted automatically after each request.
- **Migrations:** tables are created at start-up, and newer optional columns are
  added automatically. Use Alembic (`backend_api/alembic/`) for any other schema changes.
- **Operations:** configure log rotation and disk-usage alerts.

## Project website

The website in `website/` is deployed separately from the backend by
`.github/workflows/website.yml`. It runs on every push to `main` that changes
`website/`. To turn it on the first time, open the repository's
**Settings → Pages** and set **Source** to **GitHub Actions**. The site is then
published at <https://mattjunior039.github.io/PillBox/>. See
[website/README.md](../website/README.md) to run it locally.
