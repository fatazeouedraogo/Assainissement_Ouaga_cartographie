"""Télécharge bâtiments, eau et routes OpenStreetMap d'une emprise pour exclure les faux positifs.

  python scripts/fetch_osm_masks.py --bbox 12.36,-1.53,12.37,-1.52 --out masques.json
"""
import argparse
import json
import urllib.parse
import urllib.request

OVERPASS = "https://overpass-api.de/api/interpreter"


def fetch(bbox):
    s, w, n, e = bbox
    q = f"""[out:json][timeout:120];
(
  way["building"]({s},{w},{n},{e});
  way["natural"="water"]({s},{w},{n},{e});
  way["waterway"~"^(river|stream|canal|drain|ditch)$"]({s},{w},{n},{e});
  way["highway"~"^(motorway|trunk|primary|secondary|tertiary|residential|unclassified|service|track|path)$"]({s},{w},{n},{e});
);
out geom;"""
    data = urllib.parse.urlencode({"data": q}).encode()
    with urllib.request.urlopen(urllib.request.Request(OVERPASS, data=data), timeout=180) as r:
        return json.loads(r.read())["elements"]


def to_masks(elements):
    out = {"buildings": [], "water": [], "roads": []}
    for el in elements:
        pts = [[p["lat"], p["lon"]] for p in el.get("geometry", [])]
        t = el.get("tags", {})
        if len(pts) < 2:
            continue
        if "building" in t:
            out["buildings"].append(pts)
        elif t.get("natural") == "water":
            out["water"].append(pts)
        elif "waterway" in t:
            out["roads"].append(pts)
        elif "highway" in t:
            out["roads"].append(pts)
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--bbox", required=True)
    ap.add_argument("--out", default="masques.json")
    a = ap.parse_args()
    masks = to_masks(fetch(tuple(float(x) for x in a.bbox.split(","))))
    json.dump(masks, open(a.out, "w"))
    print({k: len(v) for k, v in masks.items()}, "->", a.out)
