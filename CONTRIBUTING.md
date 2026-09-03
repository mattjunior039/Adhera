# Contributing

## Branching

1. Create a feature branch from `main`.
2. Keep pull requests focused and small when possible.
3. Rebase or merge `main` before opening a PR.

## Local checks before PR

### Backend

```bash
cd backend_api
source .venv/bin/activate
python -m pytest tests
```

### Mobile

```bash
cd mobile_app
flutter analyze
flutter test
```

## Secrets and local files

- Never commit `.env` files.
- Never commit service account JSON credentials.
- Never commit local SQLite DB files, uploads, logs, or build artifacts.

## Updating config keys

When adding new environment keys:

1. Add documented defaults/comments to `backend_api/.env.example`.
2. Mention the change in the pull request description.
3. Notify collaborators to update local `.env`.
