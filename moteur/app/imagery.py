from __future__ import annotations

import io
import math
import urllib.request

from PIL import Image

TILE = 256


def _tile(lat: float, lon: float, z: int) -> tuple[float, float]:
    n = 2.0**z
    x = (lon + 180.0) / 360.0 * n
    r = math.radians(lat)
    y = (1.0 - math.asinh(math.tan(r)) / math.pi) / 2.0 * n
    return x, y


def fetch_mosaic(bbox: tuple[float, float, float, float], zoom: int, template: str, user_agent: str = "ouaga-propre/1.0", max_tiles: int = 400) -> Image.Image:
    south, west, north, east = bbox
    x0f, y0f = _tile(north, west, zoom)
    x1f, y1f = _tile(south, east, zoom)
    x0, x1 = int(math.floor(x0f)), int(math.floor(x1f))
    y0, y1 = int(math.floor(y0f)), int(math.floor(y1f))
    count = (x1 - x0 + 1) * (y1 - y0 + 1)
    if count > max_tiles:
        raise ValueError(f"{count} tuiles demandées (limite {max_tiles}) : réduisez l'emprise ou le zoom")
    mosaic = Image.new("RGB", ((x1 - x0 + 1) * TILE, (y1 - y0 + 1) * TILE))
    for ty in range(y0, y1 + 1):
        for tx in range(x0, x1 + 1):
            url = template.format(z=zoom, x=tx, y=ty)
            req = urllib.request.Request(url, headers={"User-Agent": user_agent})
            with urllib.request.urlopen(req, timeout=30) as r:
                tile = Image.open(io.BytesIO(r.read())).convert("RGB")
            mosaic.paste(tile, ((tx - x0) * TILE, (ty - y0) * TILE))
    left = int(round((x0f - x0) * TILE))
    top = int(round((y0f - y0) * TILE))
    right = int(round((x1f - x0) * TILE))
    bottom = int(round((y1f - y0) * TILE))
    return mosaic.crop((left, top, max(right, left + 1), max(bottom, top + 1)))
