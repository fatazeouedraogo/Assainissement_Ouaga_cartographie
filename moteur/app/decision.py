from __future__ import annotations

import itertools
import random

from .planner import build_plan, public_plan
from .scenarios import apply_events
from .schemas import (
    CalibrateRequest,
    Params,
    ParetoRequest,
    PlanRequest,
    RecommendRequest,
)
from .simulation import simulate


def _eval(req, params: Params, hh, time_limit: int, reps: int):
    sub = PlanRequest(households=hh, dumps=req.dumps, depot=req.depot, landfill=req.landfill, params=params, time_limit_s=time_limit)
    plan = public_plan(build_plan(sub, params, hh))
    sim = simulate(hh, req.dumps, plan, params, replications=reps)["summary"]
    return plan["metrics"], sim


def _dominates(a: dict, b: dict) -> bool:
    ge = a["cost"] <= b["cost"] and a["leakage"] <= b["leakage"] and a["co2"] <= b["co2"] and a["equity"] >= b["equity"]
    gt = a["cost"] < b["cost"] or a["leakage"] < b["leakage"] or a["co2"] < b["co2"] or a["equity"] > b["equity"]
    return ge and gt


def pareto(req: ParetoRequest) -> dict:
    params, hh, _ = apply_events(req.params, req.households, req.events)
    base = params.trucks
    grid = list(itertools.product([max(1, base - 2), base, base + 3], [0.0, 2.0], [max(1, params.frequency_days - 1), params.frequency_days, params.frequency_days + 1]))
    random.Random(params.seed).shuffle(grid)
    chosen = grid[: req.candidates]
    rows = []
    for trucks, boost, freq in chosen:
        p = Params(**{**params.model_dump(), "trucks": trucks, "equity_boost": boost, "frequency_days": freq})
        m, s = _eval(req, p, hh, req.time_limit_s, 4)
        rows.append(
            {
                "trucks": trucks,
                "equity_boost": boost,
                "frequency_days": freq,
                "cost": m["cost_per_month"],
                "leakage": s["leakage_rate"]["mean"],
                "collection": s["collection_rate"]["mean"],
                "co2": m["co2_kg_per_day"],
                "equity": m["equity_index"],
                "within_budget": m["within_budget"],
            }
        )
    for r in rows:
        r["pareto"] = not any(_dominates(o, r) for o in rows if o is not r)
    rows.sort(key=lambda r: r["cost"])
    return {"points": rows}


def _score(metrics: dict, summary: dict) -> float:
    over = max(0.0, metrics["cost_per_month"] / max(metrics["budget_month"], 1.0) - 1.0)
    return summary["collection_rate"]["mean"] - summary["leakage_rate"]["mean"] - 0.5 * over - 0.2 * metrics["unserved_points"] / max(metrics["points"], 1)


def recommend(req: RecommendRequest) -> dict:
    params, hh, log = apply_events(req.params, req.households, req.events)
    has_narrow = params.narrow_access_share > 0 or any(h.narrow for h in hh)
    options = [("Ne rien changer", {})]
    options += [(f"Louer {k} camion(s) en renfort", {"trucks": params.trucks + k}) for k in (1, 2)]
    if has_narrow:
        options.append(("Renforcer avec 10 tricycles", {"tricycles": params.tricycles + 10}))
    options += [
        (f"Passer à un passage tous les {params.frequency_days + 1} jours", {"frequency_days": params.frequency_days + 1}),
        ("Doubler la capacité de la brigade Laabal", {"laabal_kg_day": max(params.laabal_kg_day, 100) * 2}),
    ]
    rows = []
    for name, change in options:
        p = Params(**{**params.model_dump(), **change})
        m, s = _eval(req, p, hh, req.time_limit_s, 5)
        rows.append(
            {
                "response": name,
                "change": change,
                "collection_rate": s["collection_rate"]["mean"],
                "leakage_rate": s["leakage_rate"]["mean"],
                "cost_per_month": m["cost_per_month"],
                "within_budget": m["within_budget"],
                "score": round(_score(m, s), 4),
            }
        )
    rows.sort(key=lambda r: -r["score"])
    ref = next(r for r in rows if r["response"] == "Ne rien changer")
    for r in rows:
        r["gain_collection_pts"] = round((r["collection_rate"] - ref["collection_rate"]) * 100, 2)
        r["extra_cost_month"] = round(r["cost_per_month"] - ref["cost_per_month"], 0)
    return {"applied_events": log, "ranking": rows, "best": rows[0]["response"]}


METRICS = {"collection_rate", "leakage_rate", "stock_in_points_kg", "dump_stock_kg", "active_dumps"}


def calibrate(req: CalibrateRequest) -> dict:
    params, hh, _ = apply_events(req.params, req.households, req.events)
    sub = PlanRequest(households=hh, dumps=req.dumps, depot=req.depot, landfill=req.landfill, params=params, time_limit_s=req.time_limit_s)
    plan = public_plan(build_plan(sub, params, hh))

    def measure(v: float) -> float:
        p = Params(**{**params.model_dump(), req.parameter: v})
        return simulate(hh, req.dumps, plan, p, replications=req.replications)["summary"][req.metric]["mean"]

    lo, hi = req.low, req.high
    f_lo, f_hi = measure(lo), measure(hi)
    trace = [{"value": lo, "metric": f_lo}, {"value": hi, "metric": f_hi}]
    bracketed = min(f_lo, f_hi) <= req.target <= max(f_lo, f_hi)
    increasing = f_hi >= f_lo
    best = lo if abs(f_lo - req.target) < abs(f_hi - req.target) else hi
    best_f = f_lo if best == lo else f_hi
    if bracketed:
        for _ in range(req.iterations):
            mid = (lo + hi) / 2
            f = measure(mid)
            trace.append({"value": round(mid, 5), "metric": f})
            if abs(f - req.target) < abs(best_f - req.target):
                best, best_f = mid, f
            if (f < req.target) == increasing:
                lo = mid
            else:
                hi = mid
    return {
        "parameter": req.parameter,
        "metric": req.metric,
        "target": req.target,
        "calibrated_value": round(best, 5),
        "achieved": round(best_f, 5),
        "bracketed": bracketed,
        "trace": trace,
        "note": None if bracketed else "La cible est hors de la plage atteignable avec ce paramètre : élargissez les bornes ou choisissez un autre paramètre.",
    }
