import io

import numpy as np
from fastapi.testclient import TestClient
from PIL import Image

from app.geo import Projection, haversine_m, in_ouaga
from app.main import app
from app.photo import hamming_hex
from app.priority import level_of
from app.routing import solve_heuristic, VehicleSpec

client = TestClient(app)


def test_projection_roundtrip():
    p = Projection(12.37, -1.52)
    xy = p.forward([12.38], [-1.50])
    lat, lon = p.inverse(xy)
    assert abs(lat[0] - 12.38) < 1e-9 and abs(lon[0] + 1.50) < 1e-9


def test_haversine_known_distance():
    d = haversine_m(12.37, -1.52, 12.38, -1.52)
    assert 1100 < float(d) < 1120


def test_bbox():
    assert in_ouaga(12.37, -1.52)
    assert not in_ouaga(14.0, -1.52)


def test_plan_covers_target_and_respects_capacity(city):
    r = client.post("/v1/plan", json={**city, "time_limit_s": 2})
    assert r.status_code == 200
    m = r.json()["metrics"]
    assert m["coverage"] >= 0.85
    assert m["overloaded_points"] == 0
    for g in r.json()["groups"]:
        for route in g["routes"]:
            assert route["load_kg"] <= 8000 + 1


def test_every_point_is_served_or_listed_unserved(city):
    r = client.post("/v1/plan", json={**city, "time_limit_s": 2}).json()
    served = {s for g in r["groups"] for rt in g["routes"] for s in rt["stops"]}
    dropped = set(r["metrics"]["unserved_ids"])
    ids = {p["id"] for p in r["points"]}
    assert served | dropped == ids
    assert not (served & dropped)


def test_fewer_trucks_lowers_collection(city):
    hi = client.post("/v1/simulate", json={**city, "params": {"trucks": 8, "replications": 6}, "time_limit_s": 2}).json()
    lo = client.post("/v1/simulate", json={**city, "params": {"trucks": 1, "replications": 6}, "time_limit_s": 2}).json()
    a = hi["simulation"]["summary"]["collection_rate"]["mean"]
    b = lo["simulation"]["summary"]["collection_rate"]["mean"]
    assert b < a


def test_rain_event_raises_leakage_and_cost(city):
    base = client.post("/v1/simulate", json={**city, "params": {"replications": 6}, "time_limit_s": 2}).json()
    rain = client.post("/v1/simulate", json={**city, "params": {"replications": 6}, "events": [{"kind": "rain_season"}], "time_limit_s": 2}).json()
    assert rain["simulation"]["summary"]["leakage_rate"]["mean"] > base["simulation"]["summary"]["leakage_rate"]["mean"]
    assert rain["plan"]["applied_events"] == ["saison des pluies"]


def test_new_district_adds_demand(city):
    extra = [{"lat": 12.39, "lon": -1.49, "weight": 1.0} for _ in range(300)]
    base = client.post("/v1/plan", json={**city, "time_limit_s": 2}).json()
    ext = client.post("/v1/plan", json={**city, "events": [{"kind": "new_district", "households": extra}], "time_limit_s": 2}).json()
    assert ext["metrics"]["demand_kg_day"] > base["metrics"]["demand_kg_day"]


def test_priority_scoring_orders_by_risk():
    body = {
        "dumps": [
            {"id": "a", "lat": 12.37, "lon": -1.52, "est_kg": 1500, "age_days": 25},
            {"id": "b", "lat": 12.40, "lon": -1.50, "est_kg": 40, "age_days": 1},
        ],
        "pois": [{"kind": "school", "lat": 12.3702, "lon": -1.5201}, {"kind": "drain", "lat": 12.3703, "lon": -1.5199}],
    }
    s = client.post("/v1/priority/score", json=body).json()["scores"]
    assert s[0]["score"] > s[1]["score"]
    assert level_of(85) == "critical" and level_of(10) == "low"


def test_photo_endpoint_and_hash_stability():
    rng = np.random.default_rng(5)
    img = Image.fromarray(rng.integers(0, 255, (420, 520, 3), dtype=np.uint8))
    buf = io.BytesIO()
    img.save(buf, "JPEG")
    r = client.post("/v1/photo/analyze", files={"file": ("a.jpg", buf.getvalue(), "image/jpeg")})
    assert r.status_code == 200
    a = r.json()["phash"]
    buf2 = io.BytesIO()
    img.resize((470, 380)).save(buf2, "JPEG")
    b = client.post("/v1/photo/analyze", files={"file": ("b.jpg", buf2.getvalue(), "image/jpeg")}).json()["phash"]
    assert hamming_hex(a, b) <= 10


def test_photo_rejects_garbage_bytes():
    r = client.post("/v1/photo/analyze", files={"file": ("x.jpg", b"not an image", "image/jpeg")})
    assert r.json()["valid_image"] is False


def test_heuristic_router_respects_capacity():
    dist = np.array([[0, 100, 200, 300], [100, 0, 150, 250], [200, 150, 0, 120], [300, 250, 120, 0]], dtype=float)
    spec = VehicleSpec("C1", "truck", 0, 1, 500, 5.0, 0.3, 0.0, 10_000)
    routes, dropped = solve_heuristic(dist, [2, 3], {2: 400, 3: 400}, [spec, spec], {})
    assert all(r.load_kg <= 500 for r in routes)
    assert not dropped


def test_compare_returns_deltas(city):
    body = {
        **{k: city[k] for k in ("households", "depot", "landfill", "dumps")},
        "base_params": {"replications": 4},
        "scenarios": [{"name": "A"}, {"name": "B", "params": {"trucks": 10}}],
        "time_limit_s": 2,
    }
    r = client.post("/v1/scenarios/compare", json=body).json()
    assert len(r["scenarios"]) == 2 and "delta_vs_first" in r["scenarios"][1]


def test_assistant_parses_french_questions():
    r = client.post("/v1/assistant/parse", json={"question": "Et si on avait 3 camions de plus pendant la saison des pluies ?"}).json()
    kinds = {e["kind"] for e in r["events"]}
    assert kinds == {"more_trucks", "rain_season"}
    assert [e for e in r["events"] if e["kind"] == "more_trucks"][0]["value"] == 3
    r = client.post("/v1/assistant/parse", json={"question": "Un camion en panne et le budget réduit de 20 %"}).json()
    assert {e["kind"] for e in r["events"]} == {"truck_breakdown", "budget_cut"}
    r = client.post("/v1/assistant/parse", json={"question": "passage tous les 3 jours avec 12 tricycles"}).json()
    assert r["params"] == {"frequency_days": 3, "tricycles": 12}
    assert client.post("/v1/assistant/parse", json={"question": "bonjour tout le monde"}).json()["recognized"] is False


def test_valorisation_and_exposure_metrics(city):
    off = client.post("/v1/simulate", json={**city, "params": {"replications": 4}, "time_limit_s": 2}).json()["simulation"]["summary"]
    on = client.post("/v1/simulate", json={**city, "params": {"replications": 4, "organic_recovery": 0.6, "plastic_recovery": 0.5}, "time_limit_s": 2}).json()["simulation"]["summary"]
    assert off["revenue_month"]["mean"] == 0
    assert on["revenue_month"]["mean"] > 0 and on["diverted_kg"]["mean"] > 0
    assert "exposed_people" in on


def test_risk_map_ranks_recurrent_zone_first(city):
    hist = [{"lat": 12.372, "lon": -1.519, "recurrence": True}] * 6 + [{"lat": 12.372, "lon": -1.5185}] * 3
    r = client.post("/v1/predict/risk", json={"households": city["households"], "history": hist, "top": 5}).json()
    assert len(r["cells"]) == 5
    top = r["cells"][0]
    assert abs(top["lat"] - 12.372) < 0.004 and abs(top["lon"] + 1.519) < 0.004


def test_satellite_candidates_find_textured_patch():
    rng = np.random.default_rng(1)
    img = np.full((240, 240, 3), (90, 140, 70), dtype=np.uint8)
    img[96:132, 120:156] = rng.integers(40, 230, (36, 36, 3), dtype=np.uint8)
    buf = io.BytesIO()
    Image.fromarray(img).save(buf, "PNG")
    r = client.post("/v1/satellite/candidates", files={"file": ("t.png", buf.getvalue(), "image/png")}, data={"south": 12.30, "west": -1.60, "north": 12.40, "east": -1.50}).json()
    assert r["candidates"]
    c = r["candidates"][0]
    assert 12.30 < c["lat"] < 12.40 and -1.60 < c["lon"] < -1.50
    assert abs(c["lon"] - (-1.60 + 138 / 240 * 0.10)) < 0.01


def test_recommend_ranks_responses(city):
    r = client.post("/v1/recommend", json={**city, "params": {"trucks": 3}, "events": [{"kind": "truck_breakdown", "value": 1}], "time_limit_s": 2}).json()
    assert r["ranking"][0]["score"] >= r["ranking"][-1]["score"]
    assert any(x["response"] == "Ne rien changer" for x in r["ranking"])


def test_calibration_recovers_known_parameter(city):
    truth = 0.6
    target = client.post("/v1/simulate", json={**city, "params": {"subscription_rate": truth, "replications": 6, "precollectors": 30, "trucks": 1}, "time_limit_s": 2}).json()["simulation"]["summary"]["leakage_rate"]["mean"]
    r = client.post("/v1/calibrate", json={**city, "params": {"precollectors": 30, "trucks": 1}, "metric": "leakage_rate", "target": target, "parameter": "subscription_rate", "low": 0.05, "high": 0.95, "time_limit_s": 2, "iterations": 8}).json()
    assert r["bracketed"] is True
    assert abs(r["achieved"] - target) < 0.01


def test_pareto_marks_non_dominated(city):
    r = client.post("/v1/pareto", json={**city, "candidates": 4, "time_limit_s": 1}).json()
    assert 1 <= sum(p["pareto"] for p in r["points"]) <= len(r["points"])


def _patch_image():
    rng = np.random.default_rng(1)
    img = np.full((240, 240, 3), (90, 140, 70), dtype=np.uint8)
    img[96:132, 120:156] = rng.integers(40, 230, (36, 36, 3), dtype=np.uint8)
    buf = io.BytesIO()
    Image.fromarray(img).save(buf, "PNG")
    return buf.getvalue()


BBOX = dict(south=12.30, west=-1.60, north=12.40, east=-1.50)
PATCH = (12.3525, -1.5425)


def test_masks_exclude_textured_patch_inside_building():
    import json

    base = client.post("/v1/satellite/candidates", files={"file": ("t.png", _patch_image(), "image/png")}, data=BBOX).json()
    assert base["candidates"]
    masks = {"buildings": [[[12.350, -1.545], [12.350, -1.540], [12.355, -1.540], [12.355, -1.545]]]}
    r = client.post("/v1/satellite/candidates", files={"file": ("t.png", _patch_image(), "image/png")}, data={**BBOX, "masks": json.dumps(masks)}).json()
    assert r["stats"]["excluded"]["buildings"] > 0
    assert len(r["candidates"]) < len(base["candidates"])
    assert not any(abs(c["lat"] - PATCH[0]) < 0.002 and abs(c["lon"] - PATCH[1]) < 0.002 for c in r["candidates"])


def test_road_mask_excludes_candidates_on_road():
    import json

    masks = {"roads": [[[12.3525, -1.5500], [12.3525, -1.5350]]]}
    r = client.post("/v1/satellite/candidates", files={"file": ("t.png", _patch_image(), "image/png")}, data={**BBOX, "masks": json.dumps(masks), "road_width_m": 400}).json()
    assert r["stats"]["excluded"]["roads"] > 0


def test_risk_raises_score_of_nearby_candidate():
    import json

    plain = client.post("/v1/satellite/candidates", files={"file": ("t.png", _patch_image(), "image/png")}, data=BBOX).json()["candidates"][0]
    cells = [{"lat": PATCH[0], "lon": PATCH[1], "risk": 90.0}]
    risky = client.post("/v1/satellite/candidates", files={"file": ("t.png", _patch_image(), "image/png")}, data={**BBOX, "risk_cells": json.dumps(cells)}).json()["candidates"][0]
    assert risky["score"] > plain["score"]
    assert risky["signals"]["risk"] > 0.8


def test_merge_candidates_across_tiles():
    cands = [
        {"lat": 12.3500, "lon": -1.5200, "score": 4.0},
        {"lat": 12.35012, "lon": -1.5200, "score": 3.0},
        {"lat": 12.3600, "lon": -1.5200, "score": 2.0},
    ]
    r = client.post("/v1/satellite/merge", json={"candidates": cands, "merge_m": 40}).json()["candidates"]
    assert len(r) == 2
    assert r[0]["score"] == 4.0 and r[0]["merged"] == 1


def test_evaluation_counts_true_and_false_positives():
    truth = [{"lat": 12.3500, "lon": -1.5200}, {"lat": 12.3600, "lon": -1.5300}, {"lat": 12.3700, "lon": -1.5400}]
    cands = [
        {"lat": 12.35010, "lon": -1.5200, "score": 5.0},
        {"lat": 12.36005, "lon": -1.5300, "score": 4.0},
        {"lat": 12.3800, "lon": -1.5000, "score": 3.0},
        {"lat": 12.3900, "lon": -1.5100, "score": 1.0},
    ]
    r = client.post("/v1/satellite/evaluate", json={"candidates": cands, "truth": truth, "radius_m": 40}).json()
    row = {x["threshold"]: x for x in r["results"]}
    assert row[0.0]["tp"] == 2 and row[0.0]["fp"] == 2 and row[0.0]["fn"] == 1
    assert row[4.0]["precision"] == 1.0 and abs(row[4.0]["recall"] - 2 / 3) < 0.01
    assert r["best"]["threshold"] == 4.0
    assert len(r["missed"]) == 1


def test_evaluation_requires_truth():
    r = client.post("/v1/satellite/evaluate", json={"candidates": [], "truth": []})
    assert r.status_code == 422
