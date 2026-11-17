from __future__ import annotations

import io

import numpy as np
from PIL import Image, ImageDraw

from .geo import Projection


def _px(bbox, size):
    south, west, north, east = bbox
    w, h = size
    return lambda lat, lon: ((lon - west) / (east - west) * w, (north - lat) / (north - south) * h)


def rasterize(masks: dict | None, bbox, size, road_width_m: float = 6.0) -> dict[str, np.ndarray]:
    w, h = size
    out = {k: np.zeros((h, w), dtype=bool) for k in ("buildings", "water", "roads")}
    if not masks:
        return out
    px = _px(bbox, size)
    south, _, north, _ = bbox
    m_per_px = (north - south) * 111320.0 / h
    width = max(1, int(round(road_width_m / max(m_per_px, 1e-6))))
    for key in ("buildings", "water"):
        img = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(img)
        for ring in masks.get(key, []):
            if len(ring) >= 3:
                d.polygon([px(la, lo) for la, lo in ring], fill=255)
        out[key] = np.asarray(img) > 0
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    for line in masks.get("roads", []):
        if len(line) >= 2:
            d.line([px(la, lo) for la, lo in line], fill=255, width=width)
    out["roads"] = np.asarray(img) > 0
    return out


def merge_candidates(cands: list[dict], merge_m: float = 40.0) -> list[dict]:
    if not cands:
        return []
    lat0 = float(np.mean([c["lat"] for c in cands]))
    lon0 = float(np.mean([c["lon"] for c in cands]))
    proj = Projection(lat0, lon0)
    xy = proj.forward([c["lat"] for c in cands], [c["lon"] for c in cands])
    order = sorted(range(len(cands)), key=lambda i: -cands[i].get("score", 0))
    kept: list[int] = []
    merged_into: dict[int, int] = {}
    for i in order:
        hit = next((k for k in kept if np.hypot(*(xy[i] - xy[k])) <= merge_m), None)
        if hit is None:
            kept.append(i)
            merged_into[i] = 0
        else:
            merged_into[hit] += 1
    out = []
    for k in kept:
        c = dict(cands[k])
        c["merged"] = merged_into[k]
        out.append(c)
    return out


def _risk_at(cells: list[dict], lat: float, lon: float, reach_m: float = 150.0) -> float:
    best = 0.0
    for c in cells:
        dy = (c["lat"] - lat) * 111320.0
        dx = (c["lon"] - lon) * 111320.0 * np.cos(np.radians(lat))
        if dx * dx + dy * dy <= reach_m * reach_m:
            best = max(best, float(c["risk"]) / 100.0)
    return best


def find_candidates(
    data: bytes,
    bbox: tuple[float, float, float, float],
    block_px: int = 12,
    top: int = 30,
    masks: dict | None = None,
    risk_cells: list[dict] | None = None,
    min_score: float = 1.5,
    merge_m: float = 40.0,
    risk_weight: float = 0.5,
    road_width_m: float = 6.0,
    return_stats: bool = False,
):
    south, west, north, east = bbox
    img = np.asarray(Image.open(io.BytesIO(data)).convert("RGB"), dtype=np.float32)
    h, w, _ = img.shape
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    gray = 0.299 * r + 0.587 * g + 0.114 * b
    exg = (2 * g - r - b) / (r + g + b + 1e-6)

    gh, gw = h // block_px, w // block_px
    stats = {"blocks": int(gh * gw), "excluded": {"buildings": 0, "water": 0, "roads": 0}, "before_merge": 0}
    if gh < 3 or gw < 3:
        return ([], stats) if return_stats else []

    def blocks(a):
        return a[: gh * block_px, : gw * block_px].reshape(gh, block_px, gw, block_px)

    texture = blocks(gray).std(axis=(1, 3))
    bright = blocks(gray).mean(axis=(1, 3))
    veg = blocks(exg).mean(axis=(1, 3))

    def z(a, floor):
        med = np.median(a)
        mad = max(np.median(np.abs(a - med)) * 1.4826, floor)
        return (a - med) / mad

    zt, zv, zb = z(texture, 3.0), z(veg, 0.03), np.abs(z(bright, 8.0))
    score = 0.55 * zt - 0.30 * zv + 0.15 * zb

    excluded = np.zeros((gh, gw), dtype=bool)
    rast = rasterize(masks, bbox, (w, h), road_width_m)
    for key, mask in rast.items():
        frac = blocks(mask.astype(np.float32)).mean(axis=(1, 3))
        hit = frac > 0.5
        stats["excluded"][key] = int((hit & ~excluded).sum())
        excluded |= hit
    score = np.where(excluded, -np.inf, score)

    idxs = np.argsort(-score, axis=None)[: max(top * 6, 60)]
    raw = []
    for idx in idxs:
        i, j = divmod(int(idx), gw)
        if not np.isfinite(score[i, j]) or score[i, j] < min_score:
            continue
        lat = north - (i + 0.5) / gh * (north - south)
        lon = west + (j + 0.5) / gw * (east - west)
        risk = _risk_at(risk_cells, lat, lon) if risk_cells else 0.0
        raw.append(
            {
                "lat": float(lat),
                "lon": float(lon),
                "base_score": round(float(score[i, j]), 2),
                "score": round(float(score[i, j]) * (1.0 + risk_weight * risk), 2),
                "signals": {
                    "texture_z": round(float(zt[i, j]), 2),
                    "vegetation_z": round(float(zv[i, j]), 2),
                    "brightness_z": round(float(zb[i, j]), 2),
                    "risk": round(risk, 2),
                },
            }
        )
    stats["before_merge"] = len(raw)
    out = merge_candidates(raw, merge_m)
    out.sort(key=lambda c: -c["score"])
    out = out[:top]
    return (out, stats) if return_stats else out
