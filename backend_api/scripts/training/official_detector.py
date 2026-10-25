"""Prepare, train, and compare clear before/after images using the limited official labels."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
import shutil
from collections import Counter
from pathlib import Path

from backend_api.services.official_pill_detection import (
    PILL_CLASSES,
    compare_counts,
    load_detector,
)

IMAGE_STEM = re.compile(r"(clip_\d{3})_frame_\d{3}")


def read_labels(
    path: Path,
    *,
    drop_zero_area: bool = False,
    exclusions: list[str] | None = None,
) -> list[tuple[int, float, float, float, float]]:
    boxes = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        parts = line.split()
        if len(parts) != 5:
            raise ValueError(f"{path.name}:{number}: expected YOLO class x y width height")
        class_id = int(parts[0])
        x, y, width, height = map(float, parts[1:])
        if class_id not in range(len(PILL_CLASSES)):
            raise ValueError(f"{path.name}:{number}: unsupported class ID {class_id}")
        if not all(math.isfinite(v) for v in (x, y, width, height)):
            raise ValueError(f"{path.name}:{number}: non-finite coordinates")
        if drop_zero_area and (width == 0 or height == 0):
            if exclusions is None:
                raise ValueError("Excluding a box requires an audit destination")
            exclusions.append(f"{path.name}:{number}: excluded zero-area box: {line}")
            continue
        if not (0 <= x <= 1 and 0 <= y <= 1 and 0 < width <= 1 and 0 < height <= 1):
            raise ValueError(f"{path.name}:{number}: coordinates outside normalized range")
        # Allow the exporter rounding coordinates to six decimal places.
        if (
            min(x - width / 2, y - height / 2) < -0.000002
            or max(
                x + width / 2,
                y + height / 2,
            )
            > 1.000002
        ):
            raise ValueError(f"{path.name}:{number}: box extends beyond image")
        boxes.append((class_id, x, y, width, height))
    return boxes


def prepare_dataset(
    labels: Path,
    images: Path,
    output: Path,
    validation_clips: set[str],
    *,
    drop_zero_area: bool = False,
) -> dict[str, object]:
    labels, images, output = labels.resolve(), images.resolve(), output.resolve()
    if not labels.is_dir() or not images.is_dir():
        raise ValueError("Labels and images must both be existing directories")
    for source in (labels, images):
        if output == source or output in source.parents or source in output.parents:
            raise ValueError("Dataset output must be separate from source directories")
    if output.exists():
        raise ValueError(f"Refusing to overwrite existing dataset: {output}")
    paths = sorted(labels.glob("clip_*_frame_*.txt"))
    if not paths:
        raise ValueError("No clip_XXX_frame_XXX.txt annotations found")
    records = []
    class_counts: dict[str, Counter[int]] = {"train": Counter(), "val": Counter()}
    clip_counts: Counter[str] = Counter()
    seen_images: dict[str, str] = {}
    exclusions: list[str] = []
    normalized_labels: dict[str, list[tuple[int, float, float, float, float]]] = {}
    for path in paths:
        match = IMAGE_STEM.fullmatch(path.stem)
        if match is None:
            raise ValueError(f"Invalid annotation filename: {path.name}")
        image = images / f"{path.stem}.jpg"
        if not image.is_file():
            raise ValueError(f"No matching image for {path.name}")
        digest = hashlib.sha256(image.read_bytes()).hexdigest()
        if digest in seen_images:
            raise ValueError(f"Duplicate image content: {image.name} and {seen_images[digest]}")
        seen_images[digest] = image.name
        boxes = read_labels(path, drop_zero_area=drop_zero_area, exclusions=exclusions)
        if not boxes:
            raise ValueError(f"No valid boxes in {path.name}; review empty frames explicitly")
        normalized_labels[path.name] = boxes
        clip = match.group(1)
        split = "val" if clip in validation_clips else "train"
        clip_counts[clip] += 1
        class_counts[split].update(box[0] for box in boxes)
        records.append((path, image, clip, split, digest))
    if not validation_clips or not validation_clips.issubset(clip_counts):
        raise ValueError("Validation clips must name annotated clips")
    for split in ("train", "val"):
        if set(class_counts[split]) != set(range(len(PILL_CLASSES))):
            raise ValueError(f"Each split must contain all three classes; check {split}")

    for split in ("train", "val"):
        (output / "images" / split).mkdir(parents=True)
        (output / "labels" / split).mkdir(parents=True)
    for path, image, _, split, _ in records:
        shutil.copy2(image, output / "images" / split / image.name)
        (output / "labels" / split / path.name).write_text(
            "".join(
                f"{cls} {x:.6f} {y:.6f} {width:.6f} {height:.6f}\n"
                for cls, x, y, width, height in normalized_labels[path.name]
            ),
            encoding="utf-8",
        )
    # JSON is valid YAML and avoids a dependency for dataset preparation.
    (output / "dataset.yaml").write_text(
        json.dumps(
            {
                "path": str(output),
                "train": "images/train",
                "val": "images/val",
                "names": list(PILL_CLASSES),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    with (output / "split_manifest.csv").open("w", newline="", encoding="utf-8") as target:
        writer = csv.writer(target)
        writer.writerow(("image", "clip", "split", "image_sha256"))
        writer.writerows((image.name, clip, split, digest) for _, image, clip, split, digest in records)
    report = {
        "class_names": list(PILL_CLASSES),
        "annotated_images": len(records),
        "images_per_clip": dict(clip_counts),
        "validation_clips": sorted(validation_clips),
        "annotation_exclusions": exclusions,
        "boxes_per_split": {
            split: {name: counts[index] for index, name in enumerate(PILL_CLASSES)}
            for split, counts in class_counts.items()
        },
        "warning": "Exploratory clip-held-out split only. Session independence is NOT established. "
        "No missing annotation was converted to a background image.",
    }
    (output / "audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def compare_images(args: argparse.Namespace) -> dict[str, object]:
    if not args.confirmed_clear_views:
        raise ValueError(
            "Manually review open, unobstructed before/after views and pass --confirmed-clear-views"
        )
    if len(args.before) < 2 or len(args.after) < 2:
        raise ValueError("Provide at least two before images and two after images")
    if not 0 < args.confidence < 1:
        raise ValueError("Confidence must lie strictly between zero and one")
    paths = args.before + args.after
    digests = []
    for path in paths:
        if not path.is_file():
            raise ValueError(f"Image not found: {path}")
        digests.append(hashlib.sha256(path.read_bytes()).hexdigest())
    if len(set(digests)) != len(digests):
        raise ValueError("Before/after views must be distinct images, without repeated content")
    model = load_detector(args.checkpoint)
    phases = {}
    detection_frames = []
    for phase, phase_paths in (("before", args.before), ("after", args.after)):
        counts = []
        for path in phase_paths:
            result = model.predict(
                source=str(path),
                conf=args.confidence,
                imgsz=args.image_size,
                device=args.device,
                verbose=False,
            )[0]
            vector = [0] * len(PILL_CLASSES)
            boxes = []
            if result.boxes is not None:
                for detection in result.boxes:
                    class_id = int(detection.cls.item())
                    vector[class_id] += 1
                    boxes.append(
                        {
                            "class": PILL_CLASSES[class_id],
                            "confidence": float(detection.conf.item()),
                            "xyxy": detection.xyxy[0].tolist(),
                        }
                    )
            counts.append(vector)
            detection_frames.append(
                {
                    "phase": phase,
                    "image": str(path.resolve()),
                    "counts": dict(zip(PILL_CLASSES, vector)),
                    "detections": boxes,
                }
            )
        phases[phase] = counts
    return {
        **compare_counts(phases["before"], phases["after"]),
        "period": "PM",
        "day": None,
        "scope": "whole provided image; no automatic compartment or occlusion detection",
        "experimental": True,
        "checkpoint": str(args.checkpoint.resolve()),
        "confidence_threshold": args.confidence,
        "frames": detection_frames,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare = commands.add_parser("prepare")
    prepare.add_argument("--labels", required=True, type=Path)
    prepare.add_argument("--images", required=True, type=Path)
    prepare.add_argument("--output", required=True, type=Path)
    prepare.add_argument("--validation-clips", required=True, nargs="+")
    prepare.add_argument(
        "--drop-zero-area-boxes",
        action="store_true",
        help="Exclude accidental zero-area boxes in output copies and record each in audit.json",
    )
    train = commands.add_parser("train")
    train.add_argument("--dataset", required=True, type=Path)
    train.add_argument("--output", required=True, type=Path)
    train.add_argument("--epochs", type=int, default=40)
    train.add_argument("--image-size", type=int, default=640)
    train.add_argument("--device", default="cpu")
    compare = commands.add_parser("compare")
    compare.add_argument("--checkpoint", required=True, type=Path)
    compare.add_argument("--before", required=True, nargs="+", type=Path)
    compare.add_argument("--after", required=True, nargs="+", type=Path)
    compare.add_argument("--confirmed-clear-views", action="store_true")
    compare.add_argument("--confidence", type=float, default=0.5)
    compare.add_argument("--image-size", type=int, default=640)
    compare.add_argument("--device", default="cpu")
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            print(
                json.dumps(
                    prepare_dataset(
                        args.labels,
                        args.images,
                        args.output,
                        set(args.validation_clips),
                        drop_zero_area=args.drop_zero_area_boxes,
                    ),
                    indent=2,
                )
            )
        elif args.command == "train":
            if not args.dataset.is_file():
                raise ValueError(f"Dataset file not found: {args.dataset}")
            specification = json.loads(args.dataset.read_text(encoding="utf-8"))
            if specification.get("names") != list(PILL_CLASSES):
                raise ValueError("Use the three-class dataset generated by the prepare command")
            if args.output.exists() or args.epochs < 1 or args.image_size < 32:
                raise ValueError("Use a fresh output directory, positive epochs and image size >= 32")
            from ultralytics import YOLO, settings

            settings.update({"sync": False})
            args.output.resolve().parent.mkdir(parents=True, exist_ok=True)
            model = YOLO(str(args.output.resolve().parent / "yolov8n.pt"))
            model.train(
                data=str(args.dataset.resolve()),
                epochs=args.epochs,
                imgsz=args.image_size,
                batch=4,
                workers=0,
                device=args.device,
                project=str(args.output.resolve().parent),
                name=args.output.name,
                exist_ok=False,
                seed=42,
                deterministic=True,
                patience=15,
                fliplr=0.0,
                flipud=0.0,
                mosaic=0.0,
                optimizer="AdamW",
                lr0=0.001,
                freeze=10,
            )
            print(f"Experimental checkpoint: {args.output / 'weights' / 'best.pt'}")
        else:
            print(json.dumps(compare_images(args), indent=2))
    except (ValueError, OSError, ImportError) as exc:
        parser.exit(1, f"Official prototype command failed: {exc}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
