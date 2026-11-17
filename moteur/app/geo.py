from __future__ import annotations

import json
import math
import os
import urllib.request
from functools import lru_cache

import numpy as np

EARTH_R = 6371008.8
OUAGA_CENTER = (12.3714, -1.5197)
OUAGA_BBOX = tuple(float(x) for x in os.environ.get("COMMUNE_BBOX", "12.25,-1.70,12.50,-1.35").split(","))


def in_ouaga(lat: float, lon: float) -> bool:
    s, w, n, e = OUAGA_BBOX
    return s <= lat <= n and w <= lon <= e


class Projection:
    def __init__(self, lat0: float, lon0: float):
        self.lat0 = lat0
        self.lon0 = lon0
        self.kx = math.radians(1.0) * EARTH_R * math.cos(math.radians(lat0))
        self.ky = math.radians(1.0) * EARTH_R

    def forward(self, lat, lon):
        lat = np.asarray(lat, dtype=float)
        lon = np.asarray(lon, dtype=float)
        return np.column_stack(((lon - self.lon0) * self.kx, (lat - self.lat0) * self.ky))

    def inverse(self, xy):
        xy = np.asarray(xy, dtype=float).reshape(-1, 2)
        return self.lat0 + xy[:, 1] / self.ky, self.lon0 + xy[:, 0] / self.kx


def haversine_m(lat1, lon1, lat2, lon2):
    p1, p2 = np.radians(lat1), np.radians(lat2)
    dp = p2 - p1
    dl = np.radians(lon2) - np.radians(lon1)
    a = np.sin(dp / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dl / 2) ** 2
    return 2 * EARTH_R * np.arcsin(np.sqrt(a))


def pairwise_m(a_xy: np.ndarray, b_xy: np.ndarray, chunk: int = 2000) -> np.ndarray:
    out = np.empty((len(a_xy), len(b_xy)), dtype=np.float32)
    for i in range(0, len(a_xy), chunk):
        d = a_xy[i : i + chunk, None, :] - b_xy[None, :, :]
        out[i : i + chunk] = np.sqrt((d * d).sum(-1))
    return out


def _osrm_table(coords: list[tuple[float, float]], base_url: str) -> np.ndarray | None:
    path = ";".join(f"{lon:.6f},{lat:.6f}" for lat, lon in coords)
    url = f"{base_url.rstrip('/')}/table/v1/driving/{path}?annotations=distance"
    try:
        with urllib.request.urlopen(url, timeout=8) as r:
            data = json.loads(r.read())
        if data.get("code") != "Ok":
            return None
        return np.array(data["distances"], dtype=float)
    except Exception:
        return None


def road_matrix_m(coords: list[tuple[float, float]], detour: float = 1.35) -> tuple[np.ndarray, str]:
    base = os.environ.get("OSRM_URL")
    if base:
        m = _osrm_table(coords, base)
        if m is not None and not np.isnan(m).any():
            return m, "osrm"
    lat = np.array([c[0] for c in coords])
    lon = np.array([c[1] for c in coords])
    m = haversine_m(lat[:, None], lon[:, None], lat[None, :], lon[None, :]) * detour
    return m, "haversine"


@lru_cache(maxsize=4)
def projection_for(lat0: float, lon0: float) -> Projection:
    return Projection(lat0, lon0)
