from __future__ import annotations

import time

import numpy as np

from .geo import road_matrix_m
from .placement import Placement, place_points
from .routing import VehicleSpec, solve_stage, sweep_groups
from .schemas import GeoPoint, PlanRequest, Params


def _vehicle_specs(p: Params, kind: str, start: int, end: int, first_start: int | None = None):
    if kind == "truck":
        n, trips = p.trucks, p.trips_per_day
        cap, sp, cm, fx = p.truck_capacity_kg, p.truck_speed_kmh, p.truck_cost_km, p.truck_fixed_day
        speed = sp * (p.rain_speed_factor if p.rain else 1.0)
    else:
        n, trips = p.tricycles, p.tricycle_trips_per_day
        cap, sp, cm, fx = p.tricycle_capacity_kg, p.tricycle_speed_kmh, p.tricycle_cost_km, p.tricycle_fixed_day
        speed = sp * (p.rain_speed_factor if p.rain else 1.0)
    unload = p.unload_min * 60.0
    per_trip = max(600.0, p.truck_hours * 3600.0 / trips - unload)
    out = []
    for i in range(n):
        for t in range(trips):
            s = first_start if (t == 0 and first_start is not None) else start
            out.append(
                VehicleSpec(
                    label=f"{'C' if kind == 'truck' else 'T'}{i + 1}",
                    kind=kind,
                    start=s,
                    end=end,
                    capacity_kg=cap,
                    speed_ms=speed / 3.6,
                    cost_m=cm / 1000.0,
                    fixed=fx / trips,
                    max_s=per_trip,
                )
            )
    return out


def _submatrix(full: np.ndarray, idx: list[int]) -> np.ndarray:
    return full[np.ix_(idx, idx)]


def build_plan(req: PlanRequest, params: Params, households, force_heuristic: bool = False) -> dict:
    t0 = time.time()
    center = (req.center.lat, req.center.lon) if req.center else None
    pl: Placement = place_points(households, req.dumps, params, center)
    pts = pl.points
    n = len(pts)
    coords = [(req.depot.lat, req.depot.lon), (req.landfill.lat, req.landfill.lon)] + [(p["lat"], p["lon"]) for p in pts]
    full, source = road_matrix_m(coords, params.detour_factor)
    GARAGE, LANDFILL = 0, 1

    demand_visit = {2 + i: pts[i]["demand_kg_day"] * params.frequency_days for i in range(n)}
    pts_xy = pl.proj.forward([p["lat"] for p in pts], [p["lon"] for p in pts])
    garage_xy = pl.proj.forward([req.depot.lat], [req.depot.lon])[0]
    dem_arr = np.array([pts[i]["demand_kg_day"] for i in range(n)])
    groups = sweep_groups(pts_xy, dem_arr, garage_xy, params.frequency_days)

    service_s = {2 + i: params.service_min_per_stop * 60.0 for i in range(n)}
    narrow_idx = {i for i in range(n) if pts[i]["narrow_access"]}
    budget_ratio = 1.0
    group_results = []
    unserved_ids: list[str] = []
    per_group_limit = max(1, int(req.time_limit_s / max(1, len(groups))))

    for g, members in enumerate(groups):
        members = sorted(members)
        narrow_here = [i for i in members if i in narrow_idx]
        truck_here = [i for i in members if i not in narrow_idx]
        hub = None
        tri_routes, tri_dropped = [], []
        extra_hub_kg = 0.0

        if narrow_here and params.tricycles > 0 and truck_here:
            cx = pts_xy[narrow_here].mean(0)
            hub = min(truck_here, key=lambda i: float(np.linalg.norm(pts_xy[i] - cx)))
            idx = [GARAGE, LANDFILL] + [2 + i for i in sorted(set(narrow_here) | {hub})]
            sub = _submatrix(full, idx)
            pos = {node: k for k, node in enumerate(idx)}
            hub_k = pos[2 + hub]
            vehicles = _vehicle_specs(params, "tricycle", hub_k, hub_k)
            cust = [pos[2 + i] for i in narrow_here]
            dem = {pos[2 + i]: demand_visit[2 + i] for i in narrow_here}
            svc = {pos[2 + i]: service_s[2 + i] for i in narrow_here}
            tri_routes_raw, dropped_raw = solve_stage(sub, cust, dem, vehicles, svc, per_group_limit, force_heuristic)
            inv = {k: node for node, k in pos.items()}
            for r in tri_routes_raw:
                tri_routes.append(
                    {
                        "vehicle": r.vehicle.label,
                        "kind": "tricycle",
                        "stops": [pts[inv[s] - 2]["id"] for s in r.stops],
                        "to_hub": pts[hub]["id"],
                        "dist_km": round(r.dist_m / 1000, 3),
                        "minutes": round(r.time_s / 60, 1),
                        "load_kg": round(r.load_kg, 1),
                        "cost": r.dist_m * r.vehicle.cost_m + r.vehicle.fixed,
                    }
                )
                extra_hub_kg += r.load_kg
            tri_dropped = [pts[inv[d] - 2]["id"] for d in dropped_raw]
        elif narrow_here:
            tri_dropped = [pts[i]["id"] for i in narrow_here]

        idx = [GARAGE, LANDFILL] + [2 + i for i in truck_here]
        sub = _submatrix(full, idx)
        pos = {node: k for k, node in enumerate(idx)}
        inv = {k: node for node, k in pos.items()}
        vehicles = _vehicle_specs(params, "truck", 1, 1, first_start=0)
        cust = [pos[2 + i] for i in truck_here]
        dem = {pos[2 + i]: demand_visit[2 + i] for i in truck_here}
        if hub is not None:
            dem[pos[2 + hub]] += extra_hub_kg
        svc = {pos[2 + i]: service_s[2 + i] for i in truck_here}
        truck_routes_raw, dropped_raw = solve_stage(sub, cust, dem, vehicles, svc, per_group_limit, force_heuristic)
        truck_routes = [
            {
                "vehicle": r.vehicle.label,
                "kind": "truck",
                "stops": [pts[inv[s] - 2]["id"] for s in r.stops],
                "dist_km": round(r.dist_m / 1000, 3),
                "minutes": round(r.time_s / 60 + params.unload_min, 1),
                "load_kg": round(r.load_kg, 1),
                "cost": r.dist_m * r.vehicle.cost_m + r.vehicle.fixed,
            }
            for r in truck_routes_raw
        ]
        dropped = [pts[inv[d] - 2]["id"] for d in dropped_raw] + tri_dropped
        unserved_ids.extend(dropped)

        used_trucks = len({r["vehicle"] for r in truck_routes})
        used_tri = len({r["vehicle"] for r in tri_routes})
        km_truck = sum(r["dist_km"] for r in truck_routes)
        km_tri = sum(r["dist_km"] for r in tri_routes)
        cost = sum(r["cost"] for r in truck_routes + tri_routes)
        group_results.append(
            {
                "group": g,
                "points": [pts[i]["id"] for i in members],
                "routes": [{k: v for k, v in r.items() if k != "cost"} for r in tri_routes + truck_routes],
                "trucks_used": used_trucks,
                "tricycles_used": used_tri,
                "km_truck": round(km_truck, 2),
                "km_tricycle": round(km_tri, 2),
                "cost_day": round(cost, 0),
                "dropped": dropped,
            }
        )

    nominal = max(1, len(groups))
    cost_day = float(np.mean([g["cost_day"] for g in group_results])) if group_results else 0.0
    km_day = float(np.mean([g["km_truck"] + g["km_tricycle"] for g in group_results])) if group_results else 0.0
    cost_month = cost_day * 30.0
    if params.budget_month > 0 and cost_month > 0:
        budget_ratio = min(1.0, params.budget_month / cost_month)
    unserved_ids = sorted(set(unserved_ids))
    served_demand = sum(p["demand_kg_day"] for p in pts if p["id"] not in set(unserved_ids))
    total_demand = sum(p["demand_kg_day"] for p in pts) or 1.0

    subscribed = float(sum(h.weight for h in households)) * params.subscription_rate
    break_even = params.precollector_income_month * params.precollectors / subscribed if subscribed > 0 else 0.0
    return {
        "points": pts,
        "groups": group_results,
        "metrics": {
            **pl.metrics,
            "frequency_days": params.frequency_days,
            "km_per_day": round(km_day, 2),
            "cost_per_day": round(cost_day, 0),
            "cost_per_month": round(cost_month, 0),
            "budget_month": params.budget_month,
            "budget_ratio": round(budget_ratio, 3),
            "within_budget": bool(cost_month <= params.budget_month + 1e-6),
            "co2_kg_per_day": round(float(np.mean([g["km_truck"] for g in group_results])) * params.co2_kg_per_km_truck, 2)
            if group_results
            else 0.0,
            "subscription_break_even_month": round(break_even, 0),
            "subscription_affordability": round(break_even / params.household_income_month, 4),
            "unserved_points": len(unserved_ids),
            "unserved_ids": unserved_ids,
            "served_share_kg": round(served_demand / total_demand, 4),
            "distance_source": source,
            "solver": "ortools" if not force_heuristic and _has_ortools() else "heuristic",
            "elapsed_s": round(time.time() - t0, 2),
            "groups": nominal,
        },
        "_placement": pl,
    }


def _has_ortools() -> bool:
    from .routing import HAS_ORTOOLS

    return HAS_ORTOOLS


def public_plan(plan: dict) -> dict:
    return {k: v for k, v in plan.items() if not k.startswith("_")}
