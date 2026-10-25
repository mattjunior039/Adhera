# Sample Data

Local media used for developing and manually verifying the computer-vision pipelines. These files are inputs for development and training — they are not application source and are not required to run the API or the app.

| Path | Contents |
| --- | --- |
| `pills/` | Reference photos of individual pills, grouped by medication and strength (HEIC originals plus JPEG conversions). |
| `pillbox/` | Photos and clips of the weekly pill organizer used for orientation/compartment work. |
| `videos/` | Source clips for dose-verification video analysis. |
| `build_dataset.py` | Builds a YOLO train/val dataset from extracted frames and labels. |

## Rebuilding the YOLO training dataset

Generated datasets (`yolo_dataset/`, `yolo_dataset_raw/`) are gitignored. To rebuild:

1. Extract frames from a clip in `videos/` (e.g. with `ffmpeg`) into a working directory.
2. Label the frames in YOLO format (one `.txt` per frame).
3. Run `python3 sample_data/build_dataset.py --images <frames_dir> --labels <labels_dir>`.
4. Train with `python3 -m backend_api.scripts.training.train_yolo` (see [backend scripts](../backend_api/scripts/README.md)).
