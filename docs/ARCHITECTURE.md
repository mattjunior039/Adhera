# Architecture

Adhera's software has two parts that communicate over a REST API, plus a project website:

- **`mobile_app/`**: a Flutter app for iOS and macOS. It handles screens, the camera, on-device text recognition, and session state.
- **`backend_api/`**: a FastAPI service that runs on the local network. It handles storage, validation, business rules, label parsing, and computer vision.
- **`website/`**: the public project website (React, Vite, Three.js), published to GitHub Pages at <https://mattjunior039.github.io/PillBox/> by `.github/workflows/website.yml`.

All image processing (label photos, pill photos, and pillbox video) happens on the phone or the Adhera backend. The only external request is the drug-name lookup in NIH RxNorm, which can also use a local RxNorm file.

The backend publishes its exact API contract at `/docs` (Swagger UI) and `/openapi.json` while it is running.

## Mobile app

| Folder | Responsibility |
| --- | --- |
| `lib/main.dart`, `app.dart` | Start-up and the root `MaterialApp` |
| `lib/app_router.dart` | All routes (go_router) |
| `lib/app_config.dart` | Build-time settings such as `API_BASE_URL` |
| `lib/screens/` | One file per screen |
| `lib/widgets/` | Reusable UI: navigation, weekly schedule, dialogs, and the prescription capture and review views |
| `lib/state/` | Shared Riverpod state for adherence, alerts, the care team, and the prescription review queue |
| `lib/repositories/` | REST calls, one repository per feature area, all using the same `ApiService` |
| `lib/services/` | The Dio HTTP client and camera-frame quality analysis |
| `lib/models/` | Dart classes that match the backend JSON |

**Libraries:** Riverpod 3 (state), go_router (navigation), Dio (HTTP), `camera` (live label viewfinder), `image_picker` (gallery and video), `flutter_image_compress` and `image` (resizing), and Google ML Kit text recognition (on-device OCR).

### Screens

| Route | Screen | Purpose |
| --- | --- | --- |
| `/login` | Sign in / sign up | Create an account or sign in |
| `/dashboard` | Home | Today's schedule, quick actions, medications, pillbox contents, recent verifications, alerts, and care team |
| `/add-medication` | Add medication | Enter a medication manually or start a scan |
| `/scan-prescription` | Scan label | Capture several views of a label and review the extracted details |
| `/prescription-queue`, `/prescription-review/:id` | Prescription review | Caregiver approval or rejection |
| `/schedule` | Schedule setup | Set days and times for each medication |
| `/medication/:id` | Medication detail | View and edit a medication |
| `/analyze-pill` | Identify pill | Photograph a pill and get a suggested match |
| `/verify-video-dose`, `/dose-verification-result` | Video verification | Upload a pillbox video and review the result |
| `/capture-photo`, `/event-result` | Photo verification | Older two-row photo comparison workflow |
| `/history` | Verification history | Past video verification results |
| `/alerts`, `/caregiver`, `/settings` | Alerts, care team, settings | Missed-dose alerts, caregivers, alert phone number, sign out |

### Prescription scanning flow

1. `prescription_scan_screen.dart` controls the camera. `services/label_frame_analysis.dart` scores frames for sharpness and framing, and ML Kit reads the text on the device.
2. The selected views are sent to `/prescriptions/prepare-multi`, which returns a flattened preview of the label. The patient checks the preview before OCR runs.
3. `/prescriptions/scan` returns structured fields. The patient edits them and confirms.
4. A caregiver approves or rejects the prescription in the queue. Approval creates the medication first and only then marks the prescription approved, so a failure leaves it waiting for verification. Repeated taps cannot cause duplicate approvals.

## Backend

| Folder | Responsibility |
| --- | --- |
| `main.py` | Creates the FastAPI app, registers routers, and creates or updates tables at start-up |
| `config.py`, `database.py` | Database URL selection (SQLite or PostgreSQL) and the async SQLAlchemy engine |
| `routers/` | HTTP endpoints. They validate input, call a service, and build the response. |
| `services/` | Business rules, OCR, and computer vision. Services do not depend on FastAPI. |
| `models/` | SQLAlchemy tables |
| `schemas/` | Pydantic request and response models (the public API contract) |
| `scripts/` | Training and support commands, run with `python -m backend_api.scripts...` |
| `datasets/` | Pill reference images and a sample RxNorm file |
| `tests/` | Automated tests |

### Data model

| Table | Stores |
| --- | --- |
| `users` | Account, with a PBKDF2-SHA256 password hash |
| `medications` | Name, dosage, and instructions |
| `schedules` | Day of week and time of day for each medication |
| `dose_outcomes` | Daily status for each scheduled dose: taken, missed, partial, or unknown |
| `compartment_inventory` | 14 pillbox slots (7 days × AM/PM) with medication and pill count |
| `dose_verification_events` | Video verification results and their evidence |
| `photo_events`, `inference_results` | Pillbox photos and per-compartment change results from the photo workflow |
| `pillbox_orientation_profiles` | Preferences for the older photo workflow |

Tables are created at start-up. `init_db()` also adds any newer optional columns to an existing database, so older local databases keep working. Alembic is configured for future migrations.

### API

| Area | Endpoints |
| --- | --- |
| Accounts | `POST /users`, `GET /users/{id}`, `GET /users/by-email/{email}`, `POST /auth/login` |
| Medications and schedules | `POST /medications`, `PUT /medications/{id}`, `GET /medications/{user_id}`, `POST /schedules`, `GET /schedule/{user_id}` |
| Adherence | `POST /adherence/log`, `GET /adherence/today/{user_id}`, `POST /adherence/evaluate/{user_id}` |
| Prescriptions | `POST /prescriptions/prepare`, `POST /prescriptions/prepare-multi`, `POST /prescriptions/scan` |
| Pill analysis | `POST /pills/identify`, `POST /pills/analyze` |
| Pillbox | `GET /pillbox/{user_id}/inventory`, `POST /pillbox/{user_id}/initialize-test-inventory`, `PUT /pillbox/{user_id}/inventory/{slot_id}` |
| Video verification | `POST /dose-verification/analyze-video`, `GET /dose-verification/{user_id}`, `GET`/`PUT /pillbox-orientation/{user_id}` |
| Photo workflow | `POST /images/upload`, `POST /photo-events`, `GET /photo-events/{user_id}`, `POST /analyze/{photo_event_id}` |
| Health | `GET /health` |

## Computer vision and AI pipelines

### Prescription label reading (`services/ocr_service.py`)

1. **Quality check:** OpenCV measures blur (Laplacian variance), exposure, contrast, and skew, and rejects unreadable images with a reason.
2. **Label flattening:** the image is rotated using its EXIF data, the label outline is found, and a perspective warp flattens it. Several views are combined into one preview that the patient checks.
3. **Text recognition (on the phone):** Apple Vision (iOS) or Google ML Kit reads the text in every captured view. A curved bottle shows different text in each view, so all of it is sent together.
4. **Field extraction (`parse_label_text`):** a local parser finds the drug line (lines with a strength such as "200 MG" first), the strength, the directions (lines starting with "Take", "Apply", "Inhale", and so on), refills, prescriber, and pharmacy. If the drug name doesn't match or the directions are missing, the result is flagged for the patient to complete by hand.
5. **Drug-name check (`rxnorm_service.py`, `drug_dictionary.py`):** names are matched against the NIH **RxNorm** API (RxNav), a local RxNorm file, or both. Matching uses Jaro-Winkler similarity from `rapidfuzz`. Text that looks like instructions (for example "DAILY AS NEEDED") is rejected as a drug name.

### Pill identification (`services/pill_identity.py`, `pill_reference_service.py`)

Meta's **DINOv2** (ViT-S/14, loaded through PyTorch Hub) turns each image into a 384-number fingerprint. `/pills/identify` compares the photo with reference images in `datasets/pill_references/` using cosine similarity and returns the best match and the runner-up. The result is always marked for review.

`/pills/analyze` first finds each pill with a YOLOv8 detector (`pill_vision.py`, set with `PILL_DETECTION_MODEL_PATH`) and then fingerprints each one. If the checkpoint is missing, it returns 503.

### Video dose verification (`services/official_video_detection.py`, `video_verification_service.py`)

This is designed for a pillbox row with seven blue PM compartments, Sunday through Saturday from left to right, holding acetaminophen, ibuprofen, or iron.

1. Two YOLOv8 models run on sampled frames (4 frames per second): a **compartment segmentation** model and a **3-class pill detector**.
2. The compartments are ordered left to right and the pills are counted in each one.
3. A *before* period and an *after* period are chosen, either automatically or from timestamps the user enters. Each period needs agreement across several frames (at least three matching samples and 75% agreement).
4. The before and after counts for each medication across the seven days are compared. The result is `CANDIDATE_SINGLE_REMOVAL`, `CANDIDATE_TRANSFER`, `NO_COUNT_CHANGE`, or `INCONCLUSIVE`.

Safety rules:

- Every result requires review.
- The schedule and the compartment the user selected are never given to the models.
- Inventory and adherence records are never changed by this step.
- Uploads are limited to 50 MiB and 120 seconds.
- Only one analysis runs at a time; a request that arrives while one is running gets a 503 "busy" response.
- Each result records the SHA-256 hashes of the models it used.

Training, datasets, evaluation, and results are in [VISION_RESEARCH.md](VISION_RESEARCH.md).

### Photo comparison (older workflow, `services/inference_service.py`)

Before-and-after photos of a two-row (14-compartment) pillbox are straightened with a perspective warp, split into cells, and compared cell by cell. Glare, blur, and occluded cells are marked unreadable rather than "unchanged." `adherence_service.py` matches photos taken within ±3 hours of a scheduled dose to estimate whether it was taken. This workflow is kept separate from video verification.

## Boundaries and conventions

- Routers stay thin; business logic lives in services; schemas and database models are converted explicitly.
- All backend imports use the `backend_api.` package path. Run commands from the repository root, or start the API with `uvicorn main:app` from inside `backend_api/`.
- `sample_data/` and `backend_api/datasets/` are inputs for development and training, not application code.
- `backend_api/runs/` (model checkpoints and reports), `backend_api/uploads/`, databases, `.env`, and credentials are local-only and gitignored.
