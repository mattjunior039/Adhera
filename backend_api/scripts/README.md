# Backend Scripts

Run supported commands from the repository root so package imports resolve.

## Training

For the official blue-PM prototype, start with the
[annotation and algorithm guide](../../docs/VISION_RESEARCH.md). Its recordings
and labels must remain separate from the older prototype.

```bash
python3 -m backend_api.scripts.training.prepare_official_prototype --help
python3 -m backend_api.scripts.training.official_detector --help
python3 -m backend_api.scripts.training.official_compartments --help
python3 -m backend_api.scripts.training.evaluate_official_videos --help
```

The limited-label detector uses
`backend_api/requirements-official-vision.txt` in an isolated Python 3.12
environment. See the guide's limited-label pilot section for training results,
dataset preparation, review-only before/after inference, and known limitations.
The [polygon/video evaluation](../../docs/VISION_RESEARCH.md#polygon-and-video-evaluation)
documents the compartment segmenter, automatic versus assisted timing, the
four-clip development results, and how to reproduce scoring. Detection mAP is
not removal accuracy; expected outcomes are used only for scoring.

The following trainer is for the **legacy one-class detector** used by the
separate loose-pill photo endpoint, not official video comparison:

```bash
python3 -m backend_api.scripts.training.train_yolo --help
```

Training requires the optional machine-learning packages and suitable local datasets; see [`sample_data/README.md`](../../sample_data/README.md) for how to build the one-class YOLO dataset. The superseded two-class crop classifier and its trainer have been removed.

## Support Utilities

`seed_sample_schedule` creates the demo account (`adherasample@gmail.com` /
`AdheraDemo2026`, name "Adhera Test") if it doesn't exist and makes sure it
uses that published password. It then fills the account with a sample week:
PM quantities at 18:00 and reproducibly randomized 1-2 pill AM entries at 08:00.
The medications are labeled as demo data, not dosing advice.

```bash
python -m backend_api.scripts.seed_sample_schedule
# or target a specific database:
python -m backend_api.scripts.seed_sample_schedule \
  --database-url sqlite+aiosqlite:////absolute/path/to/backend_api/pillbox.db
```

It creates any missing tables, can be run repeatedly, keeps manually created
schedules and other accounts, and replaces old starter schedules only when they
have no recorded history. It never changes a different account that happens to
use the demo email. Potassium is not a trained vision class.

Only when intentionally starting the sample account over, add
`--reset-sample-data`. This clears that account's medication, schedule, inventory,
orientation, and activity records in one transaction while retaining its login
profile and other users. It does not delete original recording files.

`tune_ocr_quality.py` and `validate_rxnorm_local.py` are manual support tools. Check each script's arguments and source before running it against local data.

The maintained automated backend suite is in `backend_api/tests/`.