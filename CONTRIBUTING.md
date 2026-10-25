# Contributing

## Workflow

1. Create a feature branch from `main`.
2. Keep changes focused. Update the relevant documentation in the same change.
3. Run the checks below before opening a pull request.

## Checks

From the repository root:

```bash
# Backend tests
python -m unittest discover -s backend_api/tests

# Backend lint and format (Ruff, configured in backend_api/ruff.toml)
ruff check backend_api && ruff format --check backend_api

# Mobile app
cd mobile_app
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
```

## Conventions

- **Backend:** keep routers thin and put logic in `services/`. Import with the
  `backend_api.` package path. Put tests in `backend_api/tests/` and runnable
  utilities in `backend_api/scripts/`.
- **Mobile app:** use one file per screen in `lib/screens/`, reusable UI in
  `lib/widgets/`, and REST access in `lib/repositories/`.
- **Safety:** vision results must stay review-only. Never give the schedule or
  the expected answer to a model.

## Secrets and local files

Never commit `.env` files, credentials, databases, uploads, patient media,
model checkpoints in `backend_api/runs/`, or build output. `.gitignore` already
excludes them.

When you add a configuration key, document it in `backend_api/.env.example`
and mention it in the pull request.
