from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from .geo import OUAGA_CENTER, Projection, pairwise_m
from .schemas import Dump, Household, Params

RINGS = (3000.0, 6000.0)
SNAP_RADIUS_M = 80.0


@dataclass
class Placement:
    proj: Projection
    centers_xy: np.ndarray
    hh_xy: np.ndarray
    hh_w: np.ndarray
    hh_assign: np.ndarray
    hh_dist: np.ndarray
    points: list[dict]
    metrics: dict


def _kmeans_pp(xy: np.ndarray, w: np.ndarray, k: int, rng: np.random.Generator) -> np.ndarray:
    n = len(xy)
    k = min(k, n)
    first = rng.choice(n, p=w / w.sum())
    centers = [xy[first]]
    d2 = ((xy - centers[0]) ** 2).sum(1)
    for _ in range(1, k):
        p = d2 * w
        total = p.sum()
        if total <= 0:
            idx = rng.integers(n)
        else:
            idx = rng.choice(n, p=p / total)
        centers.append(xy[idx])
        d2 = np.minimum(d2, ((xy - xy[idx]) ** 2).sum(1))
    return np.array(centers)


def _assign(xy: np.ndarray, centers: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    d = pairwise_m(xy, centers)
    a = d.argmin(1)
    return a, d[np.arange(len(xy)), a].astype(float)


def _lloyd(xy, w, centers, iters=12):
    k = len(centers)
    for _ in range(iters):
        a, _ = _assign(xy, centers)
        tot = np.bincount(a, weights=w, minlength=k)
        sx = np.bincount(a, weights=w * xy[:, 0], minlength=k)
        sy = np.bincount(a, weights=w * xy[:, 1], minlength=k)
        new = centers.copy()
        ok = tot > 0
        new[ok, 0] = sx[ok] / tot[ok]
        new[ok, 1] = sy[ok] / tot[ok]
        moved = np.abs(new - centers).max()
        centers = new
        if moved < 1.0:
            break
    return centers


def _coverage(dist, w, radius):
    return float(w[dist <= radius].sum() / w.sum())


def _ring_of(dist_center: np.ndarray) -> np.ndarray:
    return np.digitize(dist_center, RINGS)


def _ring_coverage(hh_xy, hh_dist, w, center_xy, radius):
    ring = _ring_of(np.sqrt(((hh_xy - center_xy) ** 2).sum(1)))
    out = {}
    for r, name in enumerate(("inner", "middle", "outer")):
        m = ring == r
        out[name] = float(w[m & (hh_dist <= radius)].sum() / w[m].sum()) if w[m].sum() > 0 else None
    return out


def _equity(rings: dict) -> float:
    vals = [v for v in rings.values() if v is not None]
    if len(vals) < 2 or max(vals) == 0:
        return 1.0
    return float(min(vals) / max(vals))


def place_points(
    households: list[Household],
    dumps: list[Dump],
    params: Params,
    center: tuple[float, float] | None = None,
) -> Placement:
    lat = np.array([h.lat for h in households])
    lon = np.array([h.lon for h in households])
    w = np.array([h.weight for h in households], dtype=float)
    proj = Projection(float(np.average(lat, weights=w)), float(np.average(lon, weights=w)))
    xy = proj.forward(lat, lon)
    c_lat, c_lon = center or OUAGA_CENTER
    center_xy = proj.forward([c_lat], [c_lon])[0]
    kg_hh = params.persons_per_household * params.waste_kg_per_person_day
    total_kg_day = float(w.sum()) * kg_hh

    k_cap = math.ceil(total_kg_day * params.frequency_days / params.point_capacity_kg)
    k = int(np.clip(max(params.min_points, k_cap, 1), 1, min(params.max_points, len(xy))))
    rng = np.random.default_rng(params.seed)

    ring_hh = _ring_of(np.sqrt(((xy - center_xy) ** 2).sum(1)))
    w_fit = w * (1.0 + params.equity_boost * ring_hh)

    best = None
    while True:
        centers = _kmeans_pp(xy, w_fit, k, rng)
        centers = _lloyd(xy, w_fit, centers)
        assign, dist = _assign(xy, centers)
        cov = _coverage(dist, w, params.max_walk_m)
        load = np.bincount(assign, weights=w * kg_hh, minlength=len(centers)) * params.frequency_days
        overloaded = int((load > params.point_capacity_kg * 1.0).sum())
        best = (centers, assign, dist, cov, overloaded)
        if (cov >= params.target_coverage and overloaded == 0) or k >= min(params.max_points, len(xy)):
            break
        k = min(min(params.max_points, len(xy)), max(k + 1, int(math.ceil(k * 1.25))))

    centers, assign, dist, cov, overloaded = best
    snapped: dict[int, str] = {}
    if dumps:
        d_xy = proj.forward([d.lat for d in dumps], [d.lon for d in dumps])
        dd = pairwise_m(centers, d_xy)
        trial = centers.copy()
        for j in range(len(centers)):
            i = int(dd[j].argmin())
            if dd[j, i] <= SNAP_RADIUS_M:
                trial[j] = d_xy[i]
                snapped[j] = dumps[i].id
        a2, dist2 = _assign(xy, trial)
        cov2 = _coverage(dist2, w, params.max_walk_m)
        if cov2 >= cov - 0.01:
            centers, assign, dist, cov = trial, a2, dist2, cov2
        else:
            snapped = {}

    narrow_flags = _narrow_points(households, assign, w, xy, centers, params)
    p_lat, p_lon = proj.inverse(centers)
    load_day = np.bincount(assign, weights=w * kg_hh, minlength=len(centers))
    hh_count = np.bincount(assign, weights=w, minlength=len(centers))
    ring_idx = _ring_of(np.sqrt(((centers - center_xy) ** 2).sum(1)))
    ring_names = ("inner", "middle", "outer")

    points = []
    for j in range(len(centers)):
        points.append(
            {
                "id": f"P{j + 1:03d}",
                "lat": float(p_lat[j]),
                "lon": float(p_lon[j]),
                "households": float(hh_count[j]),
                "demand_kg_day": float(load_day[j]),
                "capacity_kg": float(params.point_capacity_kg),
                "narrow_access": bool(narrow_flags[j]),
                "ring": ring_names[int(ring_idx[j])],
                "on_existing_dump": snapped.get(j),
            }
        )

    rings = _ring_coverage(xy, dist, w, center_xy, params.max_walk_m)
    order = np.argsort(dist)
    cw = np.cumsum(w[order])
    p90 = float(dist[order][np.searchsorted(cw, 0.9 * cw[-1])])
    metrics = {
        "points": len(points),
        "coverage": round(cov, 4),
        "coverage_by_ring": {k_: (round(v, 4) if v is not None else None) for k_, v in rings.items()},
        "equity_index": round(_equity(rings), 4),
        "mean_walk_m": round(float(np.average(dist, weights=w)), 1),
        "p90_walk_m": round(p90, 1),
        "overloaded_points": overloaded,
        "snapped_on_dumps": len(snapped),
        "demand_kg_day": round(total_kg_day, 1),
        "target_reached": bool(cov >= params.target_coverage and overloaded == 0),
    }
    return Placement(proj, centers, xy, w, assign, dist, points, metrics)


def _narrow_points(households, assign, w, xy, centers, params) -> np.ndarray:
    k = len(centers)
    flags = np.zeros(k, dtype=bool)
    if any(h.narrow for h in households):
        nw = np.array([h.weight if h.narrow else 0.0 for h in households])
        tot = np.bincount(assign, weights=w, minlength=k)
        nar = np.bincount(assign, weights=nw, minlength=k)
        return (nar / np.maximum(tot, 1e-9)) >= 0.5
    if params.narrow_access_share <= 0 or k == 0:
        return flags
    count = np.bincount(assign, weights=w, minlength=k)
    spread = np.zeros(k)
    for j in range(k):
        m = assign == j
        if m.any():
            spread[j] = np.sqrt(((xy[m] - centers[j]) ** 2).sum(1).mean()) + 1.0
    density = count / (spread**2)
    n_flag = int(round(params.narrow_access_share * k))
    flags[np.argsort(-density)[:n_flag]] = True
    return flags
