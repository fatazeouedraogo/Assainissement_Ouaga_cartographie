from __future__ import annotations

import numpy as np

from .geo import Projection
from .schemas import Dump, Household, Poi

CELL_M = 150.0


def _blur(grid: np.ndarray, sigma_cells: float) -> np.ndarray:
    r = max(1, int(3 * sigma_cells))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma_cells) ** 2)
    k /= k.sum()
    out = np.apply_along_axis(lambda v: np.convolve(v, k, mode="same"), 0, grid)
    return np.apply_along_axis(lambda v: np.convolve(v, k, mode="same"), 1, out)


def _norm(a: np.ndarray) -> np.ndarray:
    m = a.max()
    return a / m if m > 0 else a


def risk_map(households: list[Household], history: list[dict], pois: list[Poi], open_dumps: list[Dump], top: int = 25) -> dict:
    lat = np.array([h.lat for h in households])
    lon = np.array([h.lon for h in households])
    w = np.array([h.weight for h in households])
    proj = Projection(float(lat.mean()), float(lon.mean()))
    xy = proj.forward(lat, lon)
    x0, y0 = xy.min(0) - 600
    x1, y1 = xy.max(0) + 600
    nx, ny = int((x1 - x0) / CELL_M) + 1, int((y1 - y0) / CELL_M) + 1
    edges = (np.linspace(x0, x0 + nx * CELL_M, nx + 1), np.linspace(y0, y0 + ny * CELL_M, ny + 1))

    dens = np.histogram2d(xy[:, 0], xy[:, 1], bins=edges, weights=w)[0]
    dens = _norm(_blur(dens, 1.0))

    past = np.zeros_like(dens)
    if history:
        hxy = proj.forward([h["lat"] for h in history], [h["lon"] for h in history])
        hw = np.array([1.0 + 2.0 * (1 if h.get("recurrence") else 0) for h in history])
        past = np.histogram2d(hxy[:, 0], hxy[:, 1], bins=edges, weights=hw)[0]
        past = _norm(_blur(past, 2.0))

    def poi_layer(kinds, sigma):
        sel = [p for p in pois if p.kind in kinds]
        if not sel:
            return np.zeros_like(dens)
        pxy = proj.forward([p.lat for p in sel], [p.lon for p in sel])
        g = np.histogram2d(pxy[:, 0], pxy[:, 1], bins=edges)[0]
        return _norm(_blur(g, sigma))

    market = poi_layer(("market",), 1.5)
    water = poi_layer(("drain", "water"), 1.2)
    risk = 0.40 * past + 0.25 * dens + 0.20 * market + 0.15 * water

    mask = np.zeros_like(risk, dtype=bool)
    if open_dumps:
        dxy = proj.forward([d.lat for d in open_dumps], [d.lon for d in open_dumps])
        ix = np.clip(((dxy[:, 0] - x0) / CELL_M).astype(int), 0, nx - 1)
        iy = np.clip(((dxy[:, 1] - y0) / CELL_M).astype(int), 0, ny - 1)
        mask[ix, iy] = True
    ranked = np.dstack(np.unravel_index(np.argsort(-np.where(mask, -1, risk), axis=None), risk.shape))[0]

    out = []
    for i, j in ranked[: top * 3]:
        if mask[i, j] or risk[i, j] <= 0:
            continue
        cx, cy = x0 + (i + 0.5) * CELL_M, y0 + (j + 0.5) * CELL_M
        la, lo = proj.inverse([[cx, cy]])
        parts = {"historique": 0.40 * past[i, j], "densité": 0.25 * dens[i, j], "marché": 0.20 * market[i, j], "eau": 0.15 * water[i, j]}
        out.append(
            {
                "lat": float(la[0]),
                "lon": float(lo[0]),
                "risk": round(float(risk[i, j]) * 100, 1),
                "main_driver": max(parts, key=parts.get),
                "radius_m": CELL_M / 2,
            }
        )
        if len(out) >= top:
            break
    return {"cells": out, "cell_m": CELL_M, "history_size": len(history), "method": "densité de noyau sur l'historique, densité de ménages, marchés et eau (indicatif)"}
