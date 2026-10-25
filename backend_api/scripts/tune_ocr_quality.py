from __future__ import annotations

import argparse
import statistics
from pathlib import Path

from backend_api.services.ocr_service import _load_image, _quality_gate


def _percentile(values: list[float], q: float) -> float:
    if not values:
        return 0.0
    if len(values) == 1:
        return values[0]
    vals = sorted(values)
    idx = (len(vals) - 1) * q
    low = int(idx)
    high = min(low + 1, len(vals) - 1)
    frac = idx - low
    return vals[low] + (vals[high] - vals[low]) * frac


def _recommend(metrics: list[dict[str, float]]) -> dict[str, float]:
    blur = [m["blur_score"] for m in metrics]
    mean_intensity = [m["mean_intensity"] for m in metrics]
    contrast = [m["contrast_score"] for m in metrics]
    skew = [m["skew_degrees"] for m in metrics]
    return {
        "blur_min": round(_percentile(blur, 0.10), 2),
        "mean_min": round(_percentile(mean_intensity, 0.05), 2),
        "mean_max": round(_percentile(mean_intensity, 0.95), 2),
        "contrast_min": round(_percentile(contrast, 0.10), 2),
        "skew_max": round(_percentile(skew, 0.90), 2),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Analyze OCR quality metrics over a folder of label images")
    parser.add_argument("images_dir", help="Directory containing label images")
    args = parser.parse_args()

    root = Path(args.images_dir).expanduser().resolve()
    if not root.exists() or not root.is_dir():
        print(f"ERROR: directory not found: {root}")
        return 1

    image_paths: list[Path] = []
    for ext in ("*.jpg", "*.jpeg", "*.png", "*.webp"):
        image_paths.extend(root.rglob(ext))

    if not image_paths:
        print("ERROR: no images found")
        return 1

    metrics: list[dict[str, float]] = []
    failed = 0
    for path in sorted(image_paths):
        try:
            img = _load_image(path)
            q = _quality_gate(img)
            metrics.append(
                {
                    "blur_score": float(q.get("blur_score", 0.0)),
                    "mean_intensity": float(q.get("mean_intensity", 0.0)),
                    "contrast_score": float(q.get("contrast_score", 0.0)),
                    "skew_degrees": float(q.get("skew_degrees", 0.0)),
                }
            )
        except Exception:
            failed += 1

    if not metrics:
        print("ERROR: all images failed to process")
        return 1

    rec = _recommend(metrics)
    print(f"images_total={len(image_paths)} images_processed={len(metrics)} images_failed={failed}")
    print("current_defaults: blur>=80.0 mean in [45.0,215.0] contrast>=25.0 skew<=8.0")
    print("recommended_percentile_thresholds:")
    for key, value in rec.items():
        print(f"  {key}: {value}")

    print("dataset_means:")
    print(f"  blur_score: {round(statistics.mean([m['blur_score'] for m in metrics]), 2)}")
    print(f"  mean_intensity: {round(statistics.mean([m['mean_intensity'] for m in metrics]), 2)}")
    print(f"  contrast_score: {round(statistics.mean([m['contrast_score'] for m in metrics]), 2)}")
    print(f"  skew_degrees: {round(statistics.mean([m['skew_degrees'] for m in metrics]), 2)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
