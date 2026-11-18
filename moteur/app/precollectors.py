from __future__ import annotations

import numpy as np

from .geo import Projection
from .placement import _assign, _kmeans_pp, _lloyd, place_points
from .schemas import Household, Params

MAX_STOPS = 120


def _tour(xy: np.ndarray, start: np.ndarray, end: np.ndarray) -> tuple[list[int], float]:
    n = len(xy)
    order, left, cur, total = [], set(range(n)), start, 0.0
    while left:
        j = min(left, key=lambda i: float(np.hypot(*(xy[i] - cur))))
        total += float(np.hypot(*(xy[j] - cur)))
        order.append(j)
        left.discard(j)
        cur = xy[j]
    total += float(np.hypot(*(end - cur)))
    improved, guard = True, 0
    path = lambda o: [start, *[xy[i] for i in o], end]
    length = lambda o: sum(float(np.hypot(*(a - b))) for a, b in zip(path(o)[:-1], path(o)[1:]))
    best = length(order)
    while improved and guard < 12 and n > 3:
        improved, guard = False, guard + 1
        for i in range(n - 1):
            for j in range(i + 1, n):
                cand = order[:i] + order[i : j + 1][::-1] + order[j + 1 :]
                l = length(cand)
                if l + 1e-6 < best:
                    order, best, improved = cand, l, True
    return order, best


def precollector_plans(households: list[Household], params: Params, center=None) -> dict:
    pl = place_points(households, [], params, center)
    n = params.precollectors
    if n <= 0:
        return {"precollectors": [], "note": "aucun pré-collecteur configuré"}
    w_sub = pl.hh_w * params.subscription_rate
    keep = w_sub > 0
    xy, w = pl.hh_xy[keep], w_sub[keep]
    if len(xy) == 0:
        return {"precollectors": [], "note": "aucun ménage abonné"}
    k = min(n, len(xy))
    rng = np.random.default_rng(params.seed)
    centers = _lloyd(xy, w, _kmeans_pp(xy, w, k, rng))
    assign, _ = _assign(xy, centers)
    kg_hh = params.persons_per_household * params.waste_kg_per_person_day
    pts_xy = pl.centers_xy
    out = []
    for z in range(k):
        m = np.where(assign == z)[0]
        if not len(m):
            continue
        order_by_w = m[np.argsort(-w[m])][:MAX_STOPS]
        zone_xy = xy[order_by_w]
        base = centers[z]
        dep_j = int(np.argmin(np.hypot(*(pts_xy - base).T)))
        order, length = _tour(zone_xy, base, pts_xy[dep_j])
        hh = float(w[m].sum())
        kg = hh * kg_hh
        minutes = length / 1000.0 / params.precollector_speed_kmh * 60.0 + len(order) * 1.5
        lat, lon = pl.proj.inverse(base)
        dl, dn = pl.proj.inverse(pts_xy[dep_j])
        stops_lat, stops_lon = pl.proj.inverse(zone_xy[order])
        out.append(
            {
                "id": f"PC{z + 1:02d}",
                "base": {"lat": float(lat[0]), "lon": float(lon[0])},
                "deposit_point": pl.points[dep_j]["id"],
                "deposit": {"lat": float(dl[0]), "lon": float(dn[0])},
                "households": round(hh, 1),
                "kg_per_day": round(kg, 1),
                "overloaded": bool(kg > params.precollector_capacity_kg),
                "stops": len(order),
                "route": [{"lat": float(a), "lon": float(b)} for a, b in zip(stops_lat, stops_lon)],
                "km": round(length / 1000.0, 2),
                "minutes": round(minutes, 0),
                "revenue_month": round(hh * params.subscription_price_month, 0),
            }
        )
    out.sort(key=lambda r: -r["kg_per_day"])
    over = sum(1 for r in out if r["overloaded"])
    return {
        "precollectors": out,
        "summary": {
            "count": len(out),
            "overloaded": over,
            "avg_revenue_month": round(float(np.mean([r["revenue_month"] for r in out])), 0),
            "price_month": params.subscription_price_month,
            "break_even_price": pl.metrics and round(params.precollector_income_month * len(out) / max(float(w.sum()), 1.0), 0),
        },
    }
