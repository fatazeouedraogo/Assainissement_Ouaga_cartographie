from __future__ import annotations

import math

import numpy as np

from .decision import _score
from .planner import build_plan, public_plan
from .scenarios import apply_events
from .schemas import LearnRequest, Params, PlanRequest
from .simulation import Model

PRIOR_CAP = 40


def _arms(params: Params, has_narrow: bool) -> dict[str, dict]:
    arms = {
        "Ne rien changer": {},
        "Louer 1 camion en renfort": {"trucks": params.trucks + 1},
        "Louer 2 camions en renfort": {"trucks": params.trucks + 2},
        f"Passer à un passage tous les {params.frequency_days + 1} jours": {"frequency_days": params.frequency_days + 1},
        "Doubler la capacité de la brigade Laabal": {"laabal_kg_day": max(params.laabal_kg_day, 100) * 2},
    }
    if has_narrow:
        arms["Renforcer avec 10 tricycles"] = {"tricycles": params.tricycles + 10}
    return arms


def learn(req: LearnRequest) -> dict:
    params, hh, log = apply_events(req.params, req.households, req.events)
    has_narrow = params.narrow_access_share > 0 or any(h.narrow for h in hh)
    arms = _arms(params, has_narrow)
    if req.arms:
        arms = {k: v for k, v in arms.items() if k in req.arms} or arms

    models, metrics = {}, {}
    for name, change in arms.items():
        p = Params(**{**params.model_dump(), **change})
        sub = PlanRequest(households=hh, dumps=req.dumps, depot=req.depot, landfill=req.landfill, params=p, sensors=req.sensors, time_limit_s=req.time_limit_s)
        plan = public_plan(build_plan(sub, p, hh))
        models[name] = Model(hh, req.dumps, plan, p)
        metrics[name] = plan["metrics"]

    stats = {}
    for name in arms:
        pr = req.prior.get(name, {})
        n0 = min(int(pr.get("n", 0)), PRIOR_CAP)
        stats[name] = {"n": n0, "mean": float(pr.get("mean", 0.0)), "m2": float(pr.get("m2", 0.0)) * (n0 / max(int(pr.get("n", 1)), 1)) if n0 else 0.0, "new": 0}

    rng = np.random.default_rng(params.seed)
    names = list(arms)
    total = sum(s["n"] for s in stats.values())
    for t in range(req.episodes):
        total += 1
        untried = [n for n in names if stats[n]["n"] == 0]
        if untried:
            pick = untried[0]
        else:
            pick = max(names, key=lambda n: stats[n]["mean"] + 0.5 * math.sqrt(2 * math.log(total) / stats[n]["n"]))
        res = models[pick].run(int(rng.integers(1, 10**9)))["final"]
        reward = res["collection_rate"] - res["leakage_rate"] - 0.5 * max(0.0, metrics[pick]["cost_per_month"] / max(metrics[pick]["budget_month"], 1.0) - 1.0)
        s = stats[pick]
        s["n"] += 1
        s["new"] += 1
        delta = reward - s["mean"]
        s["mean"] += delta / s["n"]
        s["m2"] += delta * (reward - s["mean"])

    rows = []
    for name in names:
        s = stats[name]
        std = math.sqrt(s["m2"] / (s["n"] - 1)) if s["n"] > 1 else 0.0
        rows.append(
            {
                "response": name,
                "change": arms[name],
                "pulls": s["n"],
                "new_pulls": s["new"],
                "value": round(s["mean"], 4),
                "std": round(std, 4),
                "cost_per_month": metrics[name]["cost_per_month"],
                "within_budget": metrics[name]["within_budget"],
            }
        )
    rows.sort(key=lambda r: -r["value"])
    state = {n: {"n": stats[n]["n"], "mean": stats[n]["mean"], "m2": stats[n]["m2"]} for n in names}
    return {"applied_events": log, "policy": rows, "best": rows[0]["response"], "state": state, "episodes": req.episodes}
