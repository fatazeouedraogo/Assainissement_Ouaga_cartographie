from __future__ import annotations

import math

import numpy as np

from .geo import Projection, pairwise_m
from .schemas import Dump, Poi

SIZE_KG = {"small": 50.0, "medium": 300.0, "large": 1500.0}
WEIGHTS_DRY = {"size": 0.30, "age": 0.15, "water": 0.25, "sensitive": 0.30}
WEIGHTS_RAIN = {"size": 0.25, "age": 0.10, "water": 0.40, "sensitive": 0.25}
WATER_SCALE_M = 150.0
SENSITIVE_SCALE_M = 200.0

LEVELS = ((80.0, "critical"), (60.0, "high"), (35.0, "medium"), (0.0, "low"))


def level_of(score: float) -> str:
    for threshold, name in LEVELS:
        if score >= threshold:
            return name
    return "low"


def score_dumps(dumps: list[Dump], pois: list[Poi], rain: bool = False) -> list[dict]:
    if not dumps:
        return []
    weights = WEIGHTS_RAIN if rain else WEIGHTS_DRY
    lat0 = float(np.mean([d.lat for d in dumps]))
    lon0 = float(np.mean([d.lon for d in dumps]))
    proj = Projection(lat0, lon0)
    d_xy = proj.forward([d.lat for d in dumps], [d.lon for d in dumps])

    water = [p for p in pois if p.kind in ("drain", "water")]
    sens = [p for p in pois if p.kind in ("school", "market", "health")]
    water_d = np.full(len(dumps), np.inf)
    if water:
        w_xy = proj.forward([p.lat for p in water], [p.lon for p in water])
        water_d = pairwise_m(d_xy, w_xy).min(1)
    sens_load = np.zeros(len(dumps))
    sens_near: list[list[str]] = [[] for _ in dumps]
    if sens:
        s_xy = proj.forward([p.lat for p in sens], [p.lon for p in sens])
        dist = pairwise_m(d_xy, s_xy)
        sens_load = np.exp(-dist / SENSITIVE_SCALE_M).sum(1)
        for i in range(len(dumps)):
            for j in np.where(dist[i] <= 300)[0]:
                sens_near[i].append(sens[j].kind)

    out = []
    for i, d in enumerate(dumps):
        kg = d.est_kg if d.est_kg > 0 else SIZE_KG[d.size]
        comp = {
            "size": min(1.0, math.log1p(kg) / math.log1p(2000.0)),
            "age": min(1.0, d.age_days / 30.0),
            "water": math.exp(-water_d[i] / WATER_SCALE_M) if np.isfinite(water_d[i]) else 0.0,
            "sensitive": 1.0 - math.exp(-sens_load[i]),
        }
        contrib = {k: 100.0 * weights[k] * v for k, v in comp.items()}
        total = sum(contrib.values())
        drivers = sorted(contrib.items(), key=lambda kv: -kv[1])
        out.append(
            {
                "id": d.id,
                "score": round(total, 1),
                "level": level_of(total),
                "components": {k: round(v, 3) for k, v in comp.items()},
                "contributions": {k: round(v, 1) for k, v in contrib.items()},
                "main_driver": drivers[0][0],
                "water_distance_m": None if not np.isfinite(water_d[i]) else round(float(water_d[i]), 0),
                "sensitive_sites_300m": sorted(set(sens_near[i])),
                "rain_weighting": rain,
            }
        )
        
    return out
