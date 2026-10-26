from __future__ import annotations

import argparse
import tempfile
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[2]
DEFAULT_DATA = BACKEND_DIR.parent / "sample_data" / "yolo_dataset" / "dataset.yaml"


def main() -> int:
    parser = argparse.ArgumentParser(description="Train the generic one-class pill detector.")
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA, help="YOLO dataset YAML")
    parser.add_argument("--dataset-root", type=Path, help="Override the YAML dataset root")
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--image-size", type=int, default=640)
    args = parser.parse_args()

    if not args.data.is_file():
        parser.error(f"dataset YAML not found: {args.data}")

    try:
        import yaml
        from ultralytics import YOLO
    except ImportError as exc:
        raise SystemExit("Pill detector training requires the backend ML dependencies.") from exc

    dataset = yaml.safe_load(args.data.read_text())
    dataset["path"] = str((args.dataset_root or args.data.parent).resolve())
    output_dir = BACKEND_DIR / "runs"
    output_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="adhera-yolo-") as temp_dir:
        resolved_yaml = Path(temp_dir) / "dataset.yaml"
        resolved_yaml.write_text(yaml.safe_dump(dataset, sort_keys=False))
        model = YOLO("yolov8n.pt")
        model.train(
            data=str(resolved_yaml),
            epochs=args.epochs,
            imgsz=args.image_size,
            project=str(output_dir),
            name="pill_model",
            exist_ok=True,
        )

    print(f"Detector checkpoint: {output_dir / 'pill_model' / 'weights' / 'best.pt'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
