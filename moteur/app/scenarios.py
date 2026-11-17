from __future__ import annotations

import copy

from .planner import build_plan, public_plan
from .schemas import (
    CompareRequest,
    Dump,
    Event,
    Household,
    Params,
    PlanRequest,
    SensitivityRequest,
    SimulateRequest,
)
from .simulation import simulate

PLAN_AFFECTING = {
    "trucks",
    "truck_capacity_kg",
    "trips_per_day",
    "tricycles",
    "frequency_days",
    "max_walk_m",
    "target_coverage",
    "equity_boost",
    "waste_kg_per_person_day",
    "budget_month",
}
DEFAULT_SENSITIVITY = [
    "trucks",
    "truck_capacity_kg",
    "frequency_days",
    "subscription_rate",
    "max_walk_m",
    "precollectors",
    "laabal_kg_day",
    "breakdown_prob",
    "waste_kg_per_person_day",
]


def apply_events(params: Params, households: list[Household], events: list[Event]):
    data = params.model_dump()
    hh = list(households)
    log = []
    for e in events:
        if e.kind == "truck_breakdown":
            k = int(e.value or 1)
            data["trucks"] = max(0, data["trucks"] - k)
            log.append(f"{k} camion(s) en panne")
        elif e.kind == "more_trucks":
            k = int(e.value or 1)
            data["trucks"] += k
            log.append(f"{k} camion(s) supplémentaire(s)")
        elif e.kind == "rain_season":
            data["rain"] = True
            log.append("saison des pluies")
        elif e.kind == "new_district":
            if e.households:
                hh.extend(e.households)
                log.append(f"nouveau quartier de {len(e.households)} enregistrements")
        elif e.kind == "budget_cut":
            cut = float(e.value if e.value is not None else 0.2)
            data["budget_month"] = data["budget_month"] * (1.0 - cut)
            log.append(f"budget réduit de {round(cut * 100)} %")
        elif e.kind == "subscription_drop":
            drop = float(e.value if e.value is not None else 0.2)
            data["subscription_rate"] = data["subscription_rate"] * (1.0 - drop)
            log.append(f"abonnements en baisse de {round(drop * 100)} %")
    return Params(**data), hh, log


def _request_like(base, params, households, time_limit):
    return PlanRequest(
        households=households,
        dumps=base.dumps,
        depot=base.depot,
        landfill=base.landfill,
        params=params,
        time_limit_s=time_limit,
    )


def plan_only(req: PlanRequest) -> dict:
    params, hh, log = apply_events(req.params, req.households, req.events)
    plan = build_plan(req, params, hh)
    out = public_plan(plan)
    out["applied_events"] = log
    out["effective_params"] = params.model_dump()
    return out


def plan_and_simulate(req: SimulateRequest) -> dict:
    params, hh, log = apply_events(req.params, req.households, req.events)
    if req.plan and not req.events:
        plan = req.plan
    else:
        plan = public_plan(build_plan(req, params, hh))
    sim = simulate(hh, req.dumps, plan, params)
    plan = dict(plan)
    plan["applied_events"] = log
    plan["effective_params"] = params.model_dump()
    return {"plan": plan, "simulation": sim}


def _headline(plan: dict, sim: dict) -> dict:
    m = plan["metrics"]
    s = sim["summary"]
    return {
        "points": m["points"],
        "coverage": m["coverage"],
        "equity_index": m["equity_index"],
        "cost_per_month": m["cost_per_month"],
        "within_budget": m["within_budget"],
        "budget_ratio": m["budget_ratio"],
        "km_per_day": m["km_per_day"],
        "co2_kg_per_day": m["co2_kg_per_day"],
        "unserved_points": m["unserved_points"],
        "collection_rate": s["collection_rate"],
        "leakage_rate": s["leakage_rate"],
        "active_dumps": s["active_dumps"],
        "dump_stock_kg": s["dump_stock_kg"],
        "stock_in_points_kg": s["stock_in_points_kg"],
        "exposed_people": s["exposed_people"],
        "revenue_month": s["revenue_month"],
        "diverted_kg": s["diverted_kg"],
        "subscription_break_even_month": m["subscription_break_even_month"],
    }


def compare(req: CompareRequest) -> dict:
    rows = []
    for item in req.scenarios:
        merged = {**req.base_params.model_dump(), **item.params}
        params = Params(**merged)
        sub = PlanRequest(
            households=req.households,
            dumps=req.dumps,
            depot=req.depot,
            landfill=req.landfill,
            params=params,
            events=item.events,
            time_limit_s=req.time_limit_s,
        )
        res = plan_and_simulate(SimulateRequest(**sub.model_dump()))
        rows.append(
            {
                "name": item.name,
                "applied_events": res["plan"]["applied_events"],
                "headline": _headline(res["plan"], res["simulation"]),
                "series": {
                    "dump_stock_kg": res["simulation"]["series"]["dump_stock_kg"],
                    "active_dumps": res["simulation"]["series"]["active_dumps"],
                },
            }
        )
    ref = rows[0]["headline"]
    for r in rows[1:]:
        h = r["headline"]
        r["delta_vs_first"] = {
            "collection_rate": round(h["collection_rate"]["mean"] - ref["collection_rate"]["mean"], 4),
            "leakage_rate": round(h["leakage_rate"]["mean"] - ref["leakage_rate"]["mean"], 4),
            "cost_per_month": round(h["cost_per_month"] - ref["cost_per_month"], 0),
            "equity_index": round(h["equity_index"] - ref["equity_index"], 4),
        }
    return {"scenarios": rows}


def _perturb(params: Params, key: str, delta: float):
    base = getattr(params, key)
    if isinstance(base, bool):
        return None
    if isinstance(base, int):
        step = 1 if base <= 5 else max(1, round(base * delta))
        lo, hi = max(0, base - step), base + step
    else:
        lo, hi = base * (1 - delta), base * (1 + delta)
    out = []
    for v in (lo, hi):
        try:
            out.append((v, Params(**{**params.model_dump(), key: v})))
        except Exception:
            out.append((v, None))
    return base, out


def sensitivity(req: SensitivityRequest) -> dict:
    params, hh, _ = apply_events(req.params, req.households, req.events)
    base_plan = public_plan(build_plan(req, params, hh))
    base_sim = simulate(hh, req.dumps, base_plan, params, replications=min(8, params.replications))
    b = base_sim["summary"]
    keys = req.parameters or DEFAULT_SENSITIVITY
    rows = []
    for key in keys:
        pert = _perturb(params, key, req.delta)
        if pert is None:
            continue
        base_val, variants = pert
        effects = []
        for val, p2 in variants:
            if p2 is None or val == base_val:
                continue
            if key in PLAN_AFFECTING:
                plan2 = public_plan(build_plan(_request_like(req, p2, hh, 2), p2, hh))
            else:
                plan2 = base_plan
            s2 = simulate(hh, req.dumps, plan2, p2, replications=min(6, params.replications))["summary"]
            rel_in = (val - base_val) / base_val if base_val else 0.0
            if rel_in == 0:
                continue

            def el(metric):
                ref = b[metric]["mean"]
                if abs(ref) < 1e-9:
                    return 0.0
                return ((s2[metric]["mean"] - ref) / abs(ref)) / rel_in

            effects.append(
                {
                    "value": round(float(val), 4),
                    "collection_rate": s2["collection_rate"]["mean"],
                    "leakage_rate": s2["leakage_rate"]["mean"],
                    "cost_per_month": plan2["metrics"]["cost_per_month"] if key in PLAN_AFFECTING else s2["cost_per_month"]["mean"],
                    "elasticity_collection": round(el("collection_rate"), 3),
                    "elasticity_leakage": round(el("leakage_rate"), 3),
                }
            )
        if effects:
            impact = max(max(abs(e["elasticity_collection"]), abs(e["elasticity_leakage"])) for e in effects)
            rows.append({"parameter": key, "base": base_val, "impact": round(impact, 3), "effects": effects})
    rows.sort(key=lambda r: -r["impact"])
    return {
        "baseline": {
            "collection_rate": b["collection_rate"]["mean"],
            "leakage_rate": b["leakage_rate"]["mean"],
            "cost_per_month": base_plan["metrics"]["cost_per_month"],
        },
        "ranking": rows,
    }
