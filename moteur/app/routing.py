from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

try:
    from ortools.constraint_solver import pywrapcp, routing_enums_pb2

    HAS_ORTOOLS = True
except Exception:
    HAS_ORTOOLS = False

DROP_PENALTY = 80_000_000
COST_SCALE = 10.0


@dataclass
class VehicleSpec:
    label: str
    kind: str
    start: int
    end: int
    capacity_kg: float
    speed_ms: float
    cost_m: float
    fixed: float
    max_s: float


@dataclass
class Route:
    vehicle: VehicleSpec
    stops: list[int]
    dist_m: float
    time_s: float
    load_kg: float
    loads: list[float] = field(default_factory=list)


def _route_metrics(order, spec, dist, demands, service_s):
    nodes = [spec.start, *order, spec.end]
    d = sum(dist[a, b] for a, b in zip(nodes[:-1], nodes[1:]))
    t = d / spec.speed_ms + sum(service_s.get(n, 0.0) for n in order)
    load = sum(demands.get(n, 0.0) for n in order)
    return float(d), float(t), float(load)


def _two_opt(order, spec, dist):
    if len(order) < 4:
        return order
    best = order[:]
    nodes = lambda o: [spec.start, *o, spec.end]
    improved = True
    guard = 0
    while improved and guard < 30:
        improved = False
        guard += 1
        for i in range(len(best) - 1):
            for j in range(i + 1, len(best)):
                cand = best[:i] + best[i : j + 1][::-1] + best[j + 1 :]
                a = sum(dist[x, y] for x, y in zip(nodes(best)[:-1], nodes(best)[1:]))
                b = sum(dist[x, y] for x, y in zip(nodes(cand)[:-1], nodes(cand)[1:]))
                if b + 1e-6 < a:
                    best = cand
                    improved = True
    return best


def solve_heuristic(dist, customers, demands, vehicles, service_s):
    remaining = set(customers)
    routes: list[Route] = []
    for spec in vehicles:
        if not remaining:
            break
        order: list[int] = []
        load = 0.0
        t = 0.0
        cur = spec.start
        while True:
            best, best_d = None, math.inf
            for c in remaining:
                if load + demands.get(c, 0.0) > spec.capacity_kg:
                    continue
                step = dist[cur, c] / spec.speed_ms + service_s.get(c, 0.0)
                back = dist[c, spec.end] / spec.speed_ms
                if t + step + back > spec.max_s:
                    continue
                if dist[cur, c] < best_d:
                    best, best_d = c, dist[cur, c]
            if best is None:
                break
            order.append(best)
            remaining.discard(best)
            load += demands.get(best, 0.0)
            t += dist[cur, best] / spec.speed_ms + service_s.get(best, 0.0)
            cur = best
        if order:
            order = _two_opt(order, spec, dist)
            d, tt, ld = _route_metrics(order, spec, dist, demands, service_s)
            routes.append(Route(spec, order, d, tt, ld))
    return routes, sorted(remaining)


def solve_ortools(dist, customers, demands, vehicles, service_s, time_limit_s, priority=None):
    n = dist.shape[0]
    starts = [v.start for v in vehicles]
    ends = [v.end for v in vehicles]
    manager = pywrapcp.RoutingIndexManager(n, len(vehicles), starts, ends)
    routing = pywrapcp.RoutingModel(manager)
    keep = []

    cost_cbs: dict[tuple, int] = {}
    time_cbs: dict[float, int] = {}
    for v_i, v in enumerate(vehicles):
        ck = (v.cost_m,)
        if ck not in cost_cbs:
            def make_cost(cm=v.cost_m):
                def cb(a, b):
                    return int(round(dist[manager.IndexToNode(a), manager.IndexToNode(b)] * cm * COST_SCALE)) + 1
                return cb
            f = make_cost()
            keep.append(f)
            cost_cbs[ck] = routing.RegisterTransitCallback(f)
        routing.SetArcCostEvaluatorOfVehicle(cost_cbs[ck], v_i)
        routing.SetFixedCostOfVehicle(int(v.fixed * COST_SCALE), v_i)
        if v.speed_ms not in time_cbs:
            def make_time(sp=v.speed_ms):
                def cb(a, b):
                    na, nb = manager.IndexToNode(a), manager.IndexToNode(b)
                    return int(dist[na, nb] / sp + service_s.get(na, 0.0))
                return cb
            f = make_time()
            keep.append(f)
            time_cbs[v.speed_ms] = routing.RegisterTransitCallback(f)

    horizon = int(max(v.max_s for v in vehicles)) + 1
    routing.AddDimensionWithVehicleTransits(
        [time_cbs[v.speed_ms] for v in vehicles], 0, horizon, True, "Time"
    )
    time_dim = routing.GetDimensionOrDie("Time")
    for v_i, v in enumerate(vehicles):
        time_dim.CumulVar(routing.End(v_i)).SetMax(int(v.max_s))

    def demand_cb(i):
        return int(round(demands.get(manager.IndexToNode(i), 0.0)))

    keep.append(demand_cb)
    dcb = routing.RegisterUnaryTransitCallback(demand_cb)
    routing.AddDimensionWithVehicleCapacity(dcb, 0, [int(v.capacity_kg) for v in vehicles], True, "Load")

    for c in customers:
        pen = int(DROP_PENALTY * (1.0 + 3.0 * (priority or {}).get(c, 0.0)) + demands.get(c, 0.0) * 2000)
        routing.AddDisjunction([manager.NodeToIndex(c)], pen)

    params = pywrapcp.DefaultRoutingSearchParameters()
    params.first_solution_strategy = routing_enums_pb2.FirstSolutionStrategy.PARALLEL_CHEAPEST_INSERTION
    params.local_search_metaheuristic = routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
    params.time_limit.seconds = max(1, int(time_limit_s))
    sol = routing.SolveWithParameters(params)
    if sol is None:
        return solve_heuristic(dist, customers, demands, vehicles, service_s)

    routes: list[Route] = []
    visited: set[int] = set()
    for v_i, spec in enumerate(vehicles):
        idx = routing.Start(v_i)
        order = []
        while not routing.IsEnd(idx):
            node = manager.IndexToNode(idx)
            if node in demands or node in customers:
                if node not in (spec.start, spec.end) or node in customers:
                    order.append(node)
            idx = sol.Value(routing.NextVar(idx))
        order = [o for o in order if o in customers]
        if order:
            d, t, ld = _route_metrics(order, spec, dist, demands, service_s)
            routes.append(Route(spec, order, d, t, ld))
            visited.update(order)
    dropped = sorted(set(customers) - visited)
    return routes, dropped


def solve_stage(dist, customers, demands, vehicles, service_s, time_limit_s, force_heuristic=False, priority=None):
    if not customers or not vehicles:
        return [], sorted(customers)
    if HAS_ORTOOLS and not force_heuristic:
        return solve_ortools(dist, customers, demands, vehicles, service_s, time_limit_s, priority)
    return solve_heuristic(dist, customers, demands, vehicles, service_s)


def sweep_groups(points_xy: np.ndarray, demand: np.ndarray, origin_xy: np.ndarray, groups: int) -> list[list[int]]:
    if groups <= 1:
        return [list(range(len(points_xy)))]
    ang = np.arctan2(points_xy[:, 1] - origin_xy[1], points_xy[:, 0] - origin_xy[0])
    order = np.argsort(ang)
    target = demand.sum() / groups
    out: list[list[int]] = [[] for _ in range(groups)]
    acc, g = 0.0, 0
    for i in order:
        if acc >= target * (g + 1) and g < groups - 1:
            g += 1
        out[g].append(int(i))
        acc += demand[i]
    return out
