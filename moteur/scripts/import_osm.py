"""Importe écoles, marchés, centres de santé et cours d'eau d'OpenStreetMap vers l'API Express."""
import argparse
import json
import urllib.parse
import urllib.request

BBOX = "12.25,-1.70,12.50,-1.35"
OVERPASS = "https://overpass-api.de/api/interpreter"

QUERY = f"""
[out:json][timeout:90];
(
  nwr["amenity"~"^(school|college|university)$"]({BBOX});
  nwr["amenity"="marketplace"]({BBOX});
  nwr["amenity"~"^(clinic|hospital|doctors)$"]({BBOX});
  nwr["healthcare"]({BBOX});
  way["waterway"~"^(drain|ditch|canal|stream|river)$"]({BBOX});
  nwr["natural"="water"]({BBOX});
);
out center 4000;
"""


def kind_of(tags: dict) -> str | None:
    a = tags.get("amenity", "")
    if a in ("school", "college", "university"):
        return "school"
    if a == "marketplace":
        return "market"
    if a in ("clinic", "hospital", "doctors") or "healthcare" in tags:
        return "health"
    w = tags.get("waterway", "")
    if w in ("drain", "ditch", "canal"):
        return "drain"
    if w in ("stream", "river") or tags.get("natural") == "water":
        return "water"
    return None


def fetch() -> list[dict]:
    data = urllib.parse.urlencode({"data": QUERY}).encode()
    with urllib.request.urlopen(urllib.request.Request(OVERPASS, data=data), timeout=120) as r:
        payload = json.loads(r.read())
    out = []
    for el in payload.get("elements", []):
        c = el.get("center") or {"lat": el.get("lat"), "lon": el.get("lon")}
        if c.get("lat") is None:
            continue
        kind = kind_of(el.get("tags", {}))
        if kind:
            out.append({"kind": kind, "name": el.get("tags", {}).get("name"), "lat": c["lat"], "lon": c["lon"]})
    return out


def push(api: str, token: str, items: list[dict]) -> None:
    for i in range(0, len(items), 500):
        body = json.dumps({"items": items[i : i + 500]}).encode()
        req = urllib.request.Request(
            f"{api.rstrip('/')}/api/poi/bulk",
            data=body,
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
        )
        urllib.request.urlopen(req, timeout=60).read()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", default="http://localhost:3000")
    ap.add_argument("--token", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    items = fetch()
    print(f"{len(items)} lieux récupérés")
    if not a.dry_run:
        push(a.api, a.token, items)
        print("import terminé")
