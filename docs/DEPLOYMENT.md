# Backend Deployment Notes

This backend uses OpenCV + OCR and requires system-level packages in production.

## Why this is required

- `opencv-python-headless` still links to native runtime libraries (`libgl1`, `libglib2.0-0`, etc.).
- Tesseract OCR requires the OS binary (`tesseract-ocr`) and language data (`tesseract-ocr-eng`).
- Google Vision requires cloud credentials (`GOOGLE_APPLICATION_CREDENTIALS`) or workload identity.

## Docker quick start

```bash
cd backend_api
cp .env.example .env
mkdir -p secrets
# put your service account json at backend_api/secrets/google-credentials.json

docker compose up --build
```

Health check:

```bash
curl http://localhost:8000/health
```

## Credentials options

- Local/dev: mount a service-account JSON and set `GOOGLE_APPLICATION_CREDENTIALS`.
- GCP Workload Identity / AWS IAM style runtime credentials: avoid static key files where possible.

## RxNorm integration options

- `RXNORM_LOOKUP_MODE=api`: always use RxNav API.
- `RXNORM_LOOKUP_MODE=local`: use a local JSON file only.
- `RXNORM_LOOKUP_MODE=both`: try local first, then API fallback.
- `RXNORM_ALLOWED_TTYS=SCD,SBD,IN,BN`: restrict matching to clinical drug and brand/ingredient terms.

Optional local file setup:

```bash
mkdir -p backend_api/datasets
# put your RxNorm-derived JSON into backend_api/datasets/rxnorm_names.json
```

Sample schema file:

- `backend_api/datasets/rxnorm_names.sample.json`

Validate your dataset before startup:

```bash
cd backend_api
python scripts/validate_rxnorm_local.py datasets/rxnorm_names.json
```

Set in `.env`:

```bash
RXNORM_LOOKUP_MODE=both
RXNORM_LOCAL_PATH=/app/datasets/rxnorm_names.json
RXNORM_ALLOWED_TTYS=SCD,SBD,IN,BN
RXNORM_API_TIMEOUT_SECONDS=4.0
LOCAL_FIELD_LLM_MAX_CHARS=6000
```

## OCR decision policy

- Primary engine is Google Cloud Vision `DOCUMENT_TEXT_DETECTION` on the full image.
- Spatial center filtering is applied in-memory via Vision bounding boxes (non-destructive).
- Device OCR text is fallback-only when cloud OCR fails due service outage/quota/timeout.
- Tesseract is last-resort fallback when cloud OCR is unavailable.

## OCR quality threshold tuning

Use this utility on a folder of real prescription-label photos to tune blur/exposure/contrast/skew defaults:

```bash
cd backend_api
python scripts/tune_ocr_quality.py /path/to/label-images
```

The script prints percentile-based suggested thresholds that you can use to update quality-gate defaults.

## Temp file cleanup

Prescription scan uploads are cleaned in a `finally` block in router code:

- `backend_api/routers/photo_events.py`

This prevents temp file buildup and disk exhaustion.

## Production notes

- Keep `uploads/` on durable storage if you need retention.
- Configure log rotation and disk alerts.
- Enforce request size limits at ingress/proxy.
