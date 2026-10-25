"""Train a compartment segmenter from COCO polygons, separately from the pill detector."""

from __future__ import annotations

import argparse
import json
import math
import shutil
from collections import defaultdict
from pathlib import Path


def prepare(coco_path: Path, images_dir: Path, output: Path) -> dict[str, object]:
    if output.exists():
        raise ValueError(f"Output already exists: {output}")
    data = json.loads(coco_path.read_text(encoding="utf-8"))
    categories = {item["id"] for item in data["categories"] if item["name"] == "compartment"}
    if len(categories) != 1:
        raise ValueError("Exactly one compartment category is required")
    grouped = defaultdict(list)
    for annotation in data["annotations"]:
        if annotation["category_id"] in categories:
            grouped[annotation["image_id"]].append(annotation)
    rows = []
    excluded = []
    for image in data["images"]:
        name = image["file_name"]
        if Path(name).name != name:
            raise ValueError("COCO filenames must be simple basenames")
        annotations = grouped[image["id"]]
        if len(annotations) != 7:
            excluded.append({"image": name, "reason": f"{len(annotations)} compartments, not seven"})
            continue
        if name.startswith("clip_001_"):
            split = "train"
        elif name.startswith("clip_002_"):
            split = "val"
        else:
            raise ValueError(f"Assign a clip-disjoint split explicitly for new clip: {name}")
        source = images_dir / name
        if not source.is_file():
            raise ValueError(f"Missing image: {source}")
        width, height = image["width"], image["height"]
        if width <= 0 or height <= 0:
            raise ValueError(f"Invalid image dimensions: {name}")
        labels = []
        for annotation in annotations:
            segmentation = annotation["segmentation"]
            if len(segmentation) != 1 or len(segmentation[0]) < 6 or len(segmentation[0]) % 2:
                raise ValueError(f"Expected one polygon with at least three points: {name}")
            vertices = segmentation[0]
            if not all(math.isfinite(value) for value in vertices):
                raise ValueError(f"Non-finite polygon: {name}")
            xs, ys = vertices[::2], vertices[1::2]
            x1, x2, y1, y2 = min(xs), max(xs), min(ys), max(ys)
            if not (0 <= x1 < x2 <= width and 0 <= y1 < y2 <= height):
                raise ValueError(f"Polygon outside image: {name}")
            normalized = [
                value / (width if index % 2 == 0 else height) for index, value in enumerate(vertices)
            ]
            labels.append("0 " + " ".join(f"{value:.6f}" for value in normalized) + "\n")
        rows.append((source, split, labels))
    if {row[1] for row in rows} != {"train", "val"}:
        raise ValueError("Both train and validation clips must have complete layouts")
    for split in ("train", "val"):
        (output / "images" / split).mkdir(parents=True)
        (output / "labels" / split).mkdir(parents=True)
    for source, split, labels in rows:
        shutil.copy2(source, output / "images" / split / source.name)
        (output / "labels" / split / f"{source.stem}.txt").write_text(
            "".join(labels),
            encoding="utf-8",
        )
    (output / "dataset.yaml").write_text(
        json.dumps(
            {
                "path": str(output.resolve()),
                "train": "images/train",
                "val": "images/val",
                "names": ["compartment"],
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    report = {
        "images": [{"image": row[0].name, "split": row[1]} for row in rows],
        "excluded": excluded,
        "note": "Polygons retained as segmentation labels; originals preserved. "
        "Clip-disjoint is not session-independent.",
    }
    (output / "audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--coco", required=True, type=Path)
    parser.add_argument("--images", required=True, type=Path)
    parser.add_argument("--dataset-output", required=True, type=Path)
    parser.add_argument("--run-output", required=True, type=Path)
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--device", default="mps")
    args = parser.parse_args()
    if args.epochs < 1 or args.run_output.exists():
        parser.error("Use positive epochs and a fresh run directory")
    try:
        report = prepare(args.coco, args.images, args.dataset_output)
    except (ValueError, OSError, KeyError) as exc:
        parser.exit(1, f"Compartment preparation failed: {exc}\n")
    print(json.dumps(report, indent=2), flush=True)
    from ultralytics import YOLO, settings

    settings.update({"sync": False})
    args.run_output.parent.mkdir(parents=True, exist_ok=True)
    model = YOLO(str(args.run_output.parent.resolve() / "yolov8n-seg.pt"))
    model.train(
        data=str((args.dataset_output / "dataset.yaml").resolve()),
        project=str(args.run_output.parent.resolve()),
        name=args.run_output.name,
        epochs=args.epochs,
        batch=4,
        imgsz=640,
        device=args.device,
        workers=0,
        seed=42,
        deterministic=True,
        patience=0,
        fliplr=0.0,
        flipud=0.0,
        mosaic=0.0,
        optimizer="AdamW",
        lr0=0.001,
        freeze=10,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
