"""Build a YOLO train/val dataset from extracted frames and label files.

Usage:
    python3 sample_data/build_dataset.py --images <frames_dir> --labels <labels_dir>

Frames can be extracted from the clips in ``sample_data/videos/``. Labels are
YOLO-format ``.txt`` files (one per frame); frames without a label file are
treated as background images. Output is written to
``sample_data/yolo_dataset/`` (gitignored), which
``backend_api/scripts/training/train_yolo.py`` consumes by default.
"""

import argparse
import glob
import os
import random
import shutil

SAMPLE_DATA_DIR = os.path.dirname(os.path.abspath(__file__))


def build(src_images: str, src_labels: str, dataset_dir: str, train_split: float) -> None:
    all_images = glob.glob(os.path.join(src_images, "*.jpg"))
    if not all_images:
        raise SystemExit(f"No .jpg frames found in {src_images}")
    random.shuffle(all_images)

    split_idx = int(len(all_images) * train_split)
    splits = {"train": all_images[:split_idx], "val": all_images[split_idx:]}

    for split_name, imgs in splits.items():
        os.makedirs(os.path.join(dataset_dir, "images", split_name), exist_ok=True)
        os.makedirs(os.path.join(dataset_dir, "labels", split_name), exist_ok=True)
        for img_path in imgs:
            base = os.path.splitext(os.path.basename(img_path))[0]
            shutil.copy(img_path, os.path.join(dataset_dir, "images", split_name, base + ".jpg"))

            # Copy label if it exists, else create an empty file for a background image.
            label_path = os.path.join(src_labels, base + ".txt")
            dest_label = os.path.join(dataset_dir, "labels", split_name, base + ".txt")
            if os.path.exists(label_path):
                shutil.copy(label_path, dest_label)
            else:
                open(dest_label, "w").close()

    yaml_content = f"""path: {dataset_dir}
train: images/train
val: images/val

names:
  0: pill
"""
    with open(os.path.join(dataset_dir, "dataset.yaml"), "w") as f:
        f.write(yaml_content)

    print(f"Dataset built with {len(splits['train'])} train and {len(splits['val'])} val images.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--images", required=True, help="Directory of extracted .jpg frames")
    parser.add_argument("--labels", required=True, help="Directory of YOLO .txt label files")
    parser.add_argument(
        "--output",
        default=os.path.join(SAMPLE_DATA_DIR, "yolo_dataset"),
        help="Output dataset directory (default: sample_data/yolo_dataset)",
    )
    parser.add_argument("--train-split", type=float, default=0.8, help="Train fraction (default 0.8)")
    args = parser.parse_args()
    build(args.images, args.labels, args.output, args.train_split)


if __name__ == "__main__":
    main()
