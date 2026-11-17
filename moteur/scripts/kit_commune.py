"""Prépare une nouvelle commune : bâtiments, lieux sensibles et réglages, en une commande.

Exemple :
  python scripts/kit_commune.py --api http://localhost:3000 --token JWT_ADMIN \
      --name Bobo-Dioulasso --bbox 11.12,-4.35,11.25,-4.22
"""
import argparse
import json
import urllib.parse
import random
import urllib.request

OVERPASS = "https://overpass-api.de/api/interpreter"


def post(api, token, path, payload, method="POST"):
    req = urllib.request.Request(
        f"{api.rstrip('/')}{path}",
        data=json.dumps(payload).encode(),
        method=method,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
    )
    return json.loads(urllib.request.urlopen(req, timeout=120).read() or b"{}")


def fetch_buildings(bbox):
    s, w, n, e = bbox
    q = f'[out:json][timeout:180];way["building"]({s},{w},{n},{e});out center 60000;'
    data = urllib.parse.urlencode({"data": q}).encode()
    with urllib.request.urlopen(urllib.request.Request(OVERPASS, data=data), timeout=240) as r:
        els = json.loads(r.read())["elements"]
    return [{"lat": x["center"]["lat"], "lon": x["center"]["lon"], "weight": 1} for x in els if "center" in x]


def synthetic(bbox, n=3000):
    s, w, nn, e = bbox
    rng = random.Random(1)
    cx, cy = (s + nn) / 2, (w + e) / 2
    return [{"lat": rng.gauss(cx, (nn - s) / 6), "lon": rng.gauss(cy, (e - w) / 6), "weight": 1} for _ in range(n)]


def main():
    import urllib.parse  # noqa: F401

    ap = argparse.ArgumentParser()
    ap.add_argument("--api", required=True)
    ap.add_argument("--token", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--bbox", required=True, help="sud,ouest,nord,est")
    ap.add_argument("--synthetic", action="store_true", help="données fictives si OpenStreetMap est inaccessible")
    a = ap.parse_args()
    bbox = tuple(float(x) for x in a.bbox.split(","))

    items = synthetic(bbox) if a.synthetic else fetch_buildings(bbox)
    for i in range(0, len(items), 5000):
        post(a.api, a.token, "/api/buildings/bulk", {"items": items[i : i + 5000], "source": "synthetic" if a.synthetic else "osm"})
    print(f"{a.name} : {len(items)} bâtiments importés")
    print("Étapes suivantes : fixer le garage et la décharge (PUT /api/settings/depot et /landfill), puis lancer un plan.")
    print(f"Démarrer l'API et le moteur avec COMMUNE_BBOX={a.bbox}")


if __name__ == "__main__":
    main()
