# Pillbox: Docker-First Local Setup

This repository contains:

- `backend_api/`: FastAPI backend (runs with Docker Compose).
- `mobile_app/`: Flutter client app.
- `docs/` and `datasets/`: supporting docs/data.

This README is the required setup path for private sharing and continuous collaboration.

## 1) Before You Push to GitHub

1. Create a **private** GitHub repository.
2. Confirm these are not staged:
   - `backend_api/.env`
   - `backend_api/secrets/google-credentials.json`
   - local DB/log/upload/build artifacts
3. If any real key was ever exposed, rotate it immediately in the provider console.

## 2) Required Prerequisites

Install on each developer machine:

- Git
- Docker Desktop (must be running)
- Flutter SDK (stable)
- Xcode (for iOS builds on macOS)

Verify tools:

```bash
git --version
docker --version
docker compose version
flutter --version
```

## 3) Clone the Private Repository

```bash
git clone <PRIVATE_GITHUB_REPO_URL>
cd pillbox
```

## 4) Configure Backend Environment (Docker)

From `backend_api/`:

```bash
cd backend_api
cp .env.example .env
mkdir -p secrets
```

### Google Vision credentials (required for cloud OCR)

1. Create or select a Google Cloud project.
2. Enable Vision API.
3. Create a service account with Vision permissions.
4. Download the service account JSON file.
5. Save it as `backend_api/secrets/google-credentials.json`.

In Docker, the compose file mounts `./secrets` to `/app/secrets` and sets:

- `GOOGLE_APPLICATION_CREDENTIALS=/app/secrets/google-credentials.json`

### Optional RxNorm local dataset

If you want local lookup plus API fallback:

1. Place a dataset file at `backend_api/datasets/rxnorm_names.json`.
2. Set in `.env`:
   - `RXNORM_LOOKUP_MODE=both`
   - `RXNORM_LOCAL_PATH=/app/datasets/rxnorm_names.json`

## 5) Start Backend with Docker Compose

From `backend_api/`:

```bash
docker compose up --build
```

Run detached when preferred:

```bash
docker compose up --build -d
```

Check health:

```bash
curl http://localhost:8000/health
```

Useful Docker commands:

```bash
docker compose logs -f api
docker compose restart api
docker compose down
docker compose down -v
```

## 6) Run Mobile App Locally

In a separate terminal:

```bash
cd mobile_app
flutter pub get
```

Run with explicit API URL:

### iOS Simulator (macOS)

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

### Physical Device

Use your computer LAN IP (example):

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.23:8000
```

Make sure phone and computer are on the same network and local firewall allows port `8000`.

## 7) Daily Workflow for Continuous Updates

Each time you pull changes:

```bash
git pull origin main
```

Then refresh app deps and backend containers:

```bash
cd mobile_app
flutter pub get

cd ../backend_api
docker compose up --build -d
```

If `.env.example` changed, copy new keys into your local `backend_api/.env` while preserving your own values.

## 8) Quality Checks

### Mobile checks

```bash
cd mobile_app
flutter analyze
flutter test
```

### Backend checks (inside container)

```bash
cd backend_api
docker compose exec api pytest tests
```

If `pytest` is unavailable in the image, run:

```bash
docker compose exec api python -m pytest tests
```

## 9) Sharing with Collaborators

1. Push this project to a **private** GitHub repository.
2. Add collaborator in GitHub: Settings -> Collaborators.
3. Collaborator clones repo and follows this README from section 2 onward.

## 10) Common Issues

- App cannot reach backend:
  - confirm `API_BASE_URL` matches target (iOS simulator or LAN IP).
- OCR credential error:
  - verify `backend_api/secrets/google-credentials.json` exists and is valid.
- Docker backend fails to boot:
  - inspect logs with `docker compose logs -f api` and verify `backend_api/.env` values.

