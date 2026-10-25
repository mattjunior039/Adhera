"""Stage 2 of pill identity: turn an isolated pill crop into a feature vector.

Uses Meta's DINOv2 (ViT-S/14) as a frozen feature extractor. The resulting
384-dimensional signature is meant for similarity comparison against a user's
enrolled pills, not for open-world pill identification.
"""

from __future__ import annotations

import os
from functools import lru_cache
from io import BytesIO
from typing import Any, NamedTuple

from PIL import Image

EMBEDDING_DIMENSIONS = 384

# 224 is divisible by the model's patch size of 14, so it needs no interpolation.
_INPUT_SIZE = 224
_IMAGENET_MEAN = [0.485, 0.456, 0.406]
_IMAGENET_STD = [0.229, 0.224, 0.225]


class PillEmbeddingUnavailable(RuntimeError):
    """Raised when the embedding model cannot be loaded or run."""


class _Embedder(NamedTuple):
    model: Any
    transform: Any
    device: Any


def _resolve_device(torch: Any) -> Any:
    """Prefer Apple Silicon MPS locally, but stay runnable on CUDA/CPU hosts."""
    override = os.getenv("PILL_EMBEDDING_DEVICE")
    if override:
        return torch.device(override)
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


@lru_cache(maxsize=1)
def _load() -> _Embedder:
    """Load DINOv2 and its preprocessing transform once per process, on first use.

    `lru_cache` holds the single instance instead of module-level globals, so the
    weights stay out of the module namespace and load lazily.
    """
    try:
        import torch
        from torchvision import transforms
    except ImportError as exc:  # pragma: no cover - depends on optional heavy dep
        raise PillEmbeddingUnavailable(
            "torch/torchvision are not installed; run pip install -r requirements.txt."
        ) from exc

    try:
        device = _resolve_device(torch)
        model = torch.hub.load("facebookresearch/dinov2", "dinov2_vits14")
        model = model.to(device)
        model.eval()
    except Exception as exc:  # pragma: no cover - network/weights failure
        raise PillEmbeddingUnavailable(f"Could not load DINOv2: {exc}") from exc

    transform = transforms.Compose(
        [
            transforms.Resize((_INPUT_SIZE, _INPUT_SIZE)),
            transforms.ToTensor(),
            transforms.Normalize(mean=_IMAGENET_MEAN, std=_IMAGENET_STD),
        ]
    )

    return _Embedder(model=model, transform=transform, device=device)


def preload() -> None:
    """Warm the model cache (used by the API startup hook)."""
    _load()


def generate_pill_signature(cropped_pil_image: Image.Image | bytes) -> list[float]:
    """Return a 384-dimensional DINOv2 signature for one pill image or crop."""
    import torch

    embedder = _load()

    if isinstance(cropped_pil_image, bytes):
        with Image.open(BytesIO(cropped_pil_image)) as decoded_image:
            image = decoded_image.convert("RGB")
    else:
        image = cropped_pil_image if cropped_pil_image.mode == "RGB" else cropped_pil_image.convert("RGB")
    tensor = embedder.transform(image).unsqueeze(0).to(embedder.device)

    try:
        with torch.no_grad():
            features = embedder.model(tensor)
    except Exception as exc:  # pragma: no cover - runtime inference failure
        raise PillEmbeddingUnavailable(f"Pill embedding inference failed: {exc}") from exc

    return features.squeeze(0).float().cpu().tolist()
