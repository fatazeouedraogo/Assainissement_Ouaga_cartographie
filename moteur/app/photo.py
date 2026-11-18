from __future__ import annotations

import io
import os

import numpy as np
from PIL import Image, ImageOps

_CLIP = None
CLIP_MIN_WASTE = float(os.environ.get("CLIP_MIN_WASTE", "0.35"))
WASTE_KEYS = ("garbage", "rubble", "plastic", "organic")
WASTE_TYPES = {"garbage": "household", "rubble": "rubble", "plastic": "plastic", "organic": "organic"}
LABELS = {
    "garbage": "a pile of garbage dumped on the ground outdoors",
    "rubble": "a heap of construction rubble and debris",
    "plastic": "plastic bags and plastic bottles waste",
    "organic": "rotting organic waste and food scraps",
    "clean": "a clean street or empty ground",
    "person": "a close-up photo of a person",
    "indoor": "an indoor room",
    "landscape": "a landscape, sky or vegetation",
}


def clip_status() -> str:
    if os.environ.get("USE_CLIP") != "1":
        return "disabled"
    return "ready" if _load_clip() else "error"


def interpret_clip(scores: dict, min_waste: float | None = None) -> dict:
    threshold = CLIP_MIN_WASTE if min_waste is None else min_waste
    waste_prob = sum(scores[k] for k in WASTE_KEYS)
    kind = max(WASTE_KEYS, key=lambda k: scores[k])
    return {
        "waste_likelihood": round(waste_prob, 3),
        "waste_type": WASTE_TYPES[kind],
        "not_a_dump": waste_prob < threshold,
    }


def _load_clip():
    global _CLIP
    if _CLIP is not None:
        return _CLIP or None
    if os.environ.get("USE_CLIP") != "1":
        _CLIP = False
        return None
    try:
        from transformers import CLIPModel, CLIPProcessor

        name = os.environ.get("CLIP_MODEL", "openai/clip-vit-base-patch32")
        offline = os.environ.get("CLIP_OFFLINE") == "1"
        _CLIP = (CLIPModel.from_pretrained(name, local_files_only=offline).eval(), CLIPProcessor.from_pretrained(name, local_files_only=offline))
    except Exception:
        _CLIP = False
        return None
    return _CLIP


def dhash(img: Image.Image) -> str:
    g = np.asarray(ImageOps.grayscale(img).resize((9, 8), Image.LANCZOS), dtype=np.int16)
    bits = (g[:, 1:] > g[:, :-1]).flatten()
    value = 0
    for b in bits:
        value = (value << 1) | int(b)
    return f"{value:016x}"


def hamming_hex(a: str, b: str) -> int:
    return bin(int(a, 16) ^ int(b, 16)).count("1")


def _laplacian_var(gray: np.ndarray) -> float:
    g = gray.astype(np.float32)
    lap = -4 * g[1:-1, 1:-1] + g[:-2, 1:-1] + g[2:, 1:-1] + g[1:-1, :-2] + g[1:-1, 2:]
    return float(lap.var())


def _heuristic(rgb: np.ndarray, gray: np.ndarray) -> float:
    gx = np.abs(np.diff(gray.astype(np.float32), axis=1))
    gy = np.abs(np.diff(gray.astype(np.float32), axis=0))
    edge_density = float(((gx[:-1, :] > 18) | (gy[:, :-1] > 18)).mean())
    q = (rgb // 32).reshape(-1, 3)
    codes = q[:, 0] * 64 + q[:, 1] * 8 + q[:, 2]
    hist = np.bincount(codes, minlength=512).astype(float)
    hist /= hist.sum()
    entropy = float(-(hist[hist > 0] * np.log2(hist[hist > 0])).sum()) / 9.0
    return float(np.clip(1.6 * edge_density + 0.5 * entropy - 0.15, 0.0, 1.0))


def analyze(data: bytes) -> dict:
    try:
        img = Image.open(io.BytesIO(data))
        img = ImageOps.exif_transpose(img).convert("RGB")
    except Exception:
        return {"valid_image": False, "flags": ["unreadable_image"]}

    small = img.copy()
    small.thumbnail((320, 320))
    rgb = np.asarray(small, dtype=np.uint8)
    gray = np.asarray(ImageOps.grayscale(small), dtype=np.uint8)
    brightness = float(gray.mean())
    sharp = _laplacian_var(gray)

    flags = []
    if brightness < 35:
        flags.append("too_dark")
    if brightness > 240:
        flags.append("overexposed")
    if sharp < 25:
        flags.append("too_blurry")
    if min(img.size) < 240:
        flags.append("low_resolution")

    result = {
        "valid_image": True,
        "width": img.size[0],
        "height": img.size[1],
        "brightness": round(brightness, 1),
        "sharpness": round(sharp, 1),
        "phash": dhash(img),
        "flags": flags,
    }

    clip = _load_clip()
    if clip:
        import torch

        model, proc = clip
        texts = list(LABELS.values())
        inputs = proc(text=texts, images=img, return_tensors="pt", padding=True)
        with torch.no_grad():
            probs = model(**inputs).logits_per_image.softmax(dim=1)[0].tolist()
        scores = dict(zip(LABELS.keys(), probs))
        verdict = interpret_clip(scores)
        result.update(
            {
                "method": "clip",
                "reliable": True,
                "waste_likelihood": verdict["waste_likelihood"],
                "waste_type": verdict["waste_type"],
                "scores": {k: round(v, 3) for k, v in scores.items()},
            }
        )
        if verdict["not_a_dump"]:
            result["flags"].append("not_a_dump")
    else:
        result.update(
            {
                "method": "heuristic",
                "reliable": False,
                "waste_likelihood": round(_heuristic(rgb, gray), 3),
                "waste_type": None,
            }
        )
    return result
