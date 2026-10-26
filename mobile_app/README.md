# Adhera Mobile App

The Flutter app for Adhera. It targets iOS and macOS. Project-wide setup is in
the [root README](../README.md).

## Commands

```bash
flutter pub get
flutter analyze
flutter test
```

## Running

Start the backend before signing in, then pass its address at build time:

```bash
# iOS Simulator
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000

# macOS (navigation and gallery uploads; camera recording requires iOS)
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:8000

# Physical iPhone: use your Mac's local network IP, not 127.0.0.1.
# Start the API with --host 0.0.0.0 on a trusted network.
flutter run -d <iphone-device-id> --dart-define=API_BASE_URL=http://<mac-lan-ip>:8000
```

- **Physical iPhone:** keep the phone and Mac on the same Wi-Fi and allow
  Adhera's Local Network permission. The Mac's IP address can change between
  networks. Plain HTTP on a local network is for development only.
- **Docker:** the Docker API runs separately at `http://127.0.0.1:8001` with its
  own database. Use that URL explicitly when testing it.
- **macOS sandbox:** the app has permission for local network requests and for
  files the user picks.

## Behavior notes

- **Dashboard:** adherence loads alongside account data. Inventory and
  verification history load independently, each with its own error and retry,
  so a slow request doesn't block the screen. Weekly medication rows are built
  only when a day is expanded.
- **Today's schedule:** pending doses stay visible. Taken and missed doses are
  grouped under a collapsed "Completed" section. Missed doses stay red and raise
  an alert. Instructions and Undo remain available.
- **Verification:** photo and video verification are not quick actions on the
  dashboard. Their screens and the verification history are still available.
- **Sample profile:** the demo account (`adherasample@gmail.com` / `AdheraDemo2026`,
  created by `seed_sample_schedule`) always shows a Wednesday. Its AM doses
  start as taken except ibuprofen, which starts missed and appears in Home and
  Alerts. Changes to the demo stay in the current session and never create real
  adherence records. Other accounts use the real weekday and backend data.
- **Navigation:** every secondary screen has a Back button that goes back, or
  goes Home if the screen was opened directly.
- **Branding:** the sign-in screen and the iOS/macOS icons use
  `assets/adhera_logo.png`.
