from __future__ import annotations

import math

import numpy as np

from .geo import Projection, pairwise_m
from .schemas import Dump, Household, Params

DUMP_THRESHOLD_KG = 100.0
CELL_M = 100.0
DUMP_ATTRACT_M = 300.0


class Model:
    def __init__(self, households: list[Household], dumps: list[Dump], plan: dict, params: Params):
        self.p = params
        w = np.array([h.weight for h in households], dtype=float)
        lat = np.array([h.lat for h in households])
        lon = np.array([h.lon for h in households])
        self.proj = Projection(float(np.average(lat, weights=w)), float(np.average(lon, weights=w)))
        self.hh_xy = self.proj.forward(lat, lon)
        self.w = w
        self.kg_hh = params.persons_per_household * params.waste_kg_per_person_day

        pts = plan["points"]
        self.pt_ids = [p["id"] for p in pts]
        self.pt_index = {pid: i for i, pid in enumerate(self.pt_ids)}
        self.pt_xy = self.proj.forward([p["lat"] for p in pts], [p["lon"] for p in pts])
        self.pt_cap = np.array([p["capacity_kg"] for p in pts], dtype=float)
        self.pt_fill0 = np.array([p.get("sensor_fill", 0.0) for p in pts], dtype=float) * self.pt_cap
        d = pairwise_m(self.hh_xy, self.pt_xy)
        self.pn = d.argmin(1)
        self.dn = d[np.arange(len(w)), self.pn].astype(float)
        self.pt_hh = np.bincount(self.pn, weights=w, minlength=len(pts))

        d_xy = self.proj.forward([x.lat for x in dumps], [x.lon for x in dumps]) if dumps else np.zeros((0, 2))
        self.init_dump_kg = [x.est_kg for x in dumps]
        slots = len(dumps)
        slot_xy: list[np.ndarray] = [r for r in d_xy]
        cell_slot: dict[tuple[int, int], int] = {}
        extra: list[float] = []

        def slot_for(xy_row: np.ndarray) -> int:
            nonlocal slots
            if len(d_xy):
                dd = np.sqrt(((d_xy - xy_row) ** 2).sum(1))
                j = int(dd.argmin())
                if dd[j] <= DUMP_ATTRACT_M:
                    return j
            key = (int(xy_row[0] // CELL_M), int(xy_row[1] // CELL_M))
            if key not in cell_slot:
                cell_slot[key] = slots
                slot_xy.append(np.array([(key[0] + 0.5) * CELL_M, (key[1] + 0.5) * CELL_M]))
                slots += 1
            return cell_slot[key]

        self.hh_slot = np.array([slot_for(r) for r in self.hh_xy], dtype=int)
        self.pt_slot = np.array([slot_for(r) for r in self.pt_xy], dtype=int)
        self.n_slots = slots
        self.slot_xy = np.array(slot_xy) if slot_xy else np.zeros((0, 2))

        self.groups: list[list[dict]] = []
        for g in plan["groups"]:
            routes = []
            for r in g["routes"]:
                routes.append(
                    {
                        "vehicle": r["vehicle"],
                        "kind": r["kind"],
                        "stops": [self.pt_index[s] for s in r["stops"]],
                        "hub": self.pt_index[r["to_hub"]] if r.get("to_hub") else None,
                        "cap": params.truck_capacity_kg if r["kind"] == "truck" else params.tricycle_capacity_kg,
                    }
                )
            self.groups.append(routes)
        self.group_cost = [g["cost_day"] for g in plan["groups"]]
        self.budget_ratio = plan["metrics"].get("budget_ratio", 1.0)
        self.F = max(1, len(self.groups))

    def _p_walk(self) -> np.ndarray:
        r = self.p.max_walk_m * 1.5
        base = 1.0 / (1.0 + (self.dn / r) ** 4)
        return base * (self.p.rain_walk_factor if self.p.rain else 1.0)

    def run(self, seed: int) -> dict:
        p = self.p
        rng = np.random.default_rng(seed)
        n = len(self.w)
        npts = len(self.pt_cap)
        subscribed = rng.random(n) < p.subscription_rate
        u = rng.random(n)
        walks = u < self._p_walk()
        waste_mult = p.rain_waste_factor if p.rain else 1.0
        base_kg = self.w * self.kg_hh * waste_mult
        share = self.pt_hh / max(self.pt_hh.sum(), 1e-9)
        pc_cap = share * p.precollectors * p.precollector_capacity_kg

        fill = self.pt_fill0.copy()
        dump_kg = np.zeros(self.n_slots)
        dump_kg[: len(self.init_dump_kg)] = self.init_dump_kg
        broken: dict[str, int] = {}

        cum = dict(produced=0.0, collected=0.0, cleaned=0.0, wild=0.0, overflow=0.0, cost=0.0)
        series = {k: [] for k in ("dump_stock_kg", "active_dumps", "fill_ratio", "collected_kg", "wild_kg", "cost")}

        for day in range(p.horizon_days):
            noise = rng.lognormal(mean=-0.005, sigma=0.1, size=n)
            prod = base_kg * noise
            cum["produced"] += prod.sum()

            sub_kg = np.bincount(self.pn, weights=prod * subscribed, minlength=npts)
            served = np.minimum(sub_kg, pc_cap)
            ratio = np.divide(served, sub_kg, out=np.zeros_like(served), where=sub_kg > 0)
            via_pc = prod * subscribed * ratio[self.pn]
            rest = prod - via_pc
            walk_dep = rest * walks
            wild_hh = rest * ~walks

            fill += np.bincount(self.pn, weights=via_pc + walk_dep, minlength=npts)
            over = np.maximum(fill - self.pt_cap, 0.0)
            fill -= over
            wild_today = float(wild_hh.sum() + over.sum())
            cum["overflow"] += float(over.sum())
            dump_kg += np.bincount(self.hh_slot, weights=wild_hh, minlength=self.n_slots)
            dump_kg += np.bincount(self.pt_slot, weights=over, minlength=self.n_slots)
            cum["wild"] += wild_today

            collected_today = 0.0
            cost_today = 0.0
            routes = self.groups[day % self.F]
            if routes and rng.random() < self.budget_ratio:
                for label, until in list(broken.items()):
                    if until <= day:
                        del broken[label]
                trucks_seen = {r["vehicle"] for r in routes if r["kind"] == "truck"}
                for label in trucks_seen:
                    if label not in broken and rng.random() < p.breakdown_prob:
                        broken[label] = day + p.repair_days
                done = 0
                ordered = sorted(routes, key=lambda r: 0 if r["kind"] == "tricycle" else 1)
                for r in ordered:
                    if r["kind"] == "truck" and r["vehicle"] in broken:
                        continue
                    done += 1
                    room = r["cap"]
                    for s in r["stops"]:
                        take = min(fill[s], room)
                        if r["hub"] is not None:
                            take = min(take, max(self.pt_cap[r["hub"]] - fill[r["hub"]], 0.0))
                        if take <= 0:
                            continue
                        fill[s] -= take
                        room -= take
                        if r["hub"] is not None:
                            fill[r["hub"]] += take
                        else:
                            collected_today += take
                cost_today = self.group_cost[day % self.F] * (done / len(routes))
            cum["collected"] += collected_today
            cum["cost"] += cost_today

            if p.laabal_kg_day > 0 and dump_kg.sum() > 0:
                order = np.argsort(-dump_kg)
                budget = p.laabal_kg_day
                for j in order:
                    if budget <= 0 or dump_kg[j] <= 0:
                        break
                    t = min(dump_kg[j], budget)
                    dump_kg[j] -= t
                    budget -= t
                    cum["cleaned"] += t

            series["dump_stock_kg"].append(float(dump_kg.sum()))
            series["active_dumps"].append(int((dump_kg >= DUMP_THRESHOLD_KG).sum()))
            series["fill_ratio"].append(float(np.mean(fill / self.pt_cap)))
            series["collected_kg"].append(collected_today)
            series["wild_kg"].append(wild_today)
            series["cost"].append(cost_today)

        prod = max(cum["produced"], 1e-9)
        active = dump_kg >= DUMP_THRESHOLD_KG
        exposed = 0.0
        if active.any():
            d = pairwise_m(self.hh_xy, self.slot_xy[active])
            near = d.min(1) <= p.exposure_radius_m
            exposed = float((self.w[near]).sum() * p.persons_per_household)
        diverted = cum["collected"] * (p.organic_share * p.organic_recovery + p.plastic_share * p.plastic_recovery)
        revenue = cum["collected"] * (
            p.organic_share * p.organic_recovery * p.compost_price_kg + p.plastic_share * p.plastic_recovery * p.plastic_price_kg
        )
        final = {
            "exposed_people": exposed,
            "diverted_kg": diverted,
            "revenue_month": revenue / p.horizon_days * 30.0,
            "collection_rate": cum["collected"] / prod,
            "leakage_rate": cum["wild"] / prod,
            "stock_in_points_kg": float(fill.sum()),
            "cleaned_by_laabal_kg": cum["cleaned"],
            "dump_stock_kg": float(dump_kg.sum()),
            "active_dumps": series["active_dumps"][-1],
            "overflow_kg": cum["overflow"],
            "cost_total": cum["cost"],
            "cost_per_month": cum["cost"] / p.horizon_days * 30.0,
            "avg_fill_ratio": float(np.mean(series["fill_ratio"])),
        }
        return {"series": series, "final": final}


def _band(arrs: np.ndarray) -> dict:
    return {
        "mean": np.mean(arrs, axis=0).round(2).tolist(),
        "p05": np.percentile(arrs, 5, axis=0).round(2).tolist(),
        "p95": np.percentile(arrs, 95, axis=0).round(2).tolist(),
    }


def simulate(households, dumps, plan: dict, params: Params, replications: int | None = None) -> dict:
    model = Model(households, dumps, plan, params)
    reps = replications or params.replications
    runs = [model.run(params.seed + i * 977) for i in range(reps)]
    keys = ("dump_stock_kg", "active_dumps", "fill_ratio", "collected_kg", "wild_kg")
    series = {k: _band(np.array([r["series"][k] for r in runs], dtype=float)) for k in keys}
    summary = {}
    for k in runs[0]["final"]:
        v = np.array([r["final"][k] for r in runs], dtype=float)
        summary[k] = {
            "mean": round(float(v.mean()), 4),
            "p05": round(float(np.percentile(v, 5)), 4),
            "p95": round(float(np.percentile(v, 95)), 4),
        }
    return {"replications": reps, "horizon_days": params.horizon_days, "summary": summary, "series": series}
