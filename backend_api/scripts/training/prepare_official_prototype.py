"""Extract annotation candidates from the official blue-PM prototype recordings."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import shutil
import subprocess
import zipfile
from pathlib import Path

CLASS_NAMES = ("acetaminophen", "ibuprofen", "iron")
VIDEO_SUFFIXES = {".mp4", ".mov", ".m4v"}
VIDEO_FIELDS = (
    "video_id",
    "source_filename",
    "sha256",
    "duration_seconds",
    "session_id",
    "split",
    "removed_day",
    "removed_class",
    "removed_count",
    "event_type",
    "source_day",
    "destination_day",
    "transferred_class",
    "transferred_count",
    "before_start_seconds",
    "before_end_seconds",
    "after_start_seconds",
    "after_end_seconds",
    "notes",
)
FRAME_FIELDS = ("image_filename", "video_id", "requested_time_seconds", "keep", "notes")


def candidate_times(duration: float, count: int) -> list[float]:
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError("Video duration must be finite and positive")
    if count < 2:
        raise ValueError("At least two candidate frames per video are required")
    return [duration * (index + 0.5) / count for index in range(count)]


def video_duration(video: Path) -> float:
    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "json",
            str(video),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    duration = float(json.loads(result.stdout)["format"]["duration"])
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError(f"Invalid video duration for {video.name}: {duration}")
    return duration


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_csv(path: Path, fields: tuple[str, ...], rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as target:
        writer = csv.DictWriter(target, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def prepare(source: Path, output: Path, frames_per_video: int = 12) -> tuple[int, int]:
    source = source.expanduser().resolve()
    output = output.expanduser().resolve()
    if not source.is_dir():
        raise ValueError(f"Source directory not found: {source}")
    if output == source or source in output.parents or output in source.parents:
        raise ValueError("Source and output directories must be separate, not nested")
    if output.exists():
        raise ValueError(f"Output already exists; use a new directory to preserve annotations: {output}")
    candidate_times(1.0, frames_per_video)
    for executable in ("ffmpeg", "ffprobe"):
        if shutil.which(executable) is None:
            raise ValueError(f"{executable} is required on PATH")

    videos = sorted(
        path for path in source.iterdir() if path.is_file() and path.suffix.lower() in VIDEO_SUFFIXES
    )
    if not videos:
        raise ValueError(f"No MP4/MOV/M4V videos found in {source}")

    records: list[tuple[Path, float, str]] = []
    seen: dict[str, str] = {}
    for video in videos:
        digest = file_digest(video)
        if digest in seen:
            raise ValueError(f"Duplicate source recordings: {seen[digest]} and {video.name}")
        seen[digest] = video.name
        records.append((video, video_duration(video), digest))

    images_dir = output / "images"
    images_dir.mkdir(parents=True)
    video_rows: list[dict[str, object]] = []
    frame_rows: list[dict[str, object]] = []
    for index, (video, duration, digest) in enumerate(records, start=1):
        video_id = f"clip_{index:03d}"
        video_rows.append(
            {
                "video_id": video_id,
                "source_filename": video.name,
                "sha256": digest,
                "duration_seconds": round(duration, 6),
            }
        )
        for frame_index, seconds in enumerate(candidate_times(duration, frames_per_video), start=1):
            filename = f"{video_id}_frame_{frame_index:03d}.jpg"
            image_path = images_dir / filename
            subprocess.run(
                [
                    "ffmpeg",
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-nostdin",
                    "-n",
                    "-ss",
                    f"{seconds:.6f}",
                    "-i",
                    str(video),
                    "-map",
                    "0:v:0",
                    "-frames:v",
                    "1",
                    "-q:v",
                    "2",
                    str(image_path),
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            if not image_path.is_file() or image_path.stat().st_size == 0:
                raise ValueError(f"No frame decoded: {video.name} at {seconds:.6f}s")
            frame_rows.append(
                {
                    "image_filename": filename,
                    "video_id": video_id,
                    "requested_time_seconds": round(seconds, 6),
                }
            )
        print(f"[{index}/{len(videos)}] {video.name}: {duration:.2f}s", flush=True)

    write_csv(output / "video_manifest.csv", VIDEO_FIELDS, video_rows)
    write_csv(output / "frame_manifest.csv", FRAME_FIELDS, frame_rows)
    (output / "obj.names").write_text("\n".join(CLASS_NAMES) + "\n", encoding="utf-8")
    specification = {
        "prototype": "official_blue_pm",
        "period": "PM",
        "row_color": "blue",
        "compartments": 7,
        "left_to_right": ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"],
        "class_names": list(CLASS_NAMES),
        "compartment_annotation": {"category": "compartment", "format": "COCO polygons"},
        "source_directory": str(source),
        "frames_per_video": frames_per_video,
        "split_policy": "Manually group recording sessions before assigning train/val/test.",
        "annotation_guide": "docs/VISION_RESEARCH.md",
    }
    (output / "prototype.json").write_text(
        json.dumps(specification, indent=2) + "\n",
        encoding="utf-8",
    )
    with zipfile.ZipFile(output / "annotation_images.zip", "w", zipfile.ZIP_STORED) as archive:
        for row in frame_rows:
            filename = str(row["image_filename"])
            archive.write(images_dir / filename, arcname=filename)
    return len(videos), len(frame_rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--frames-per-video", type=int, default=12)
    args = parser.parse_args()
    try:
        videos, frames = prepare(args.source, args.output, args.frames_per_video)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as exc:
        if isinstance(exc, subprocess.CalledProcessError):
            parser.exit(1, f"Media command failed: {exc}\n{exc.stderr or ''}")
        parser.exit(1, f"Preparation failed: {exc}\n")
    print(f"Prepared {frames} candidate frames from {videos} videos in {args.output}")
    print("Review candidates before annotation; no training split or pill identity was guessed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
