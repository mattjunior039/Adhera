# Pillbox Mobile App

Primary project setup and collaboration instructions are documented in the root README:

- `../README.md`

## Quick local commands

```bash
flutter pub get
flutter analyze
flutter test
```

Run with explicit backend URL:

```bash
# iOS simulator
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```
