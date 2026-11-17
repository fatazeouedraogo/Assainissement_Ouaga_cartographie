from __future__ import annotations

import numpy as np

from .geo import Projection


def _match(cands: list[dict], truth: list[dict], radius_m: float, proj: Projection):
    if not cands or not truth:
        return [], list(range(len(cands))), list(range(len(truth)))
    c_xy = proj.forward([c["lat"] for c in cands], [c["lon"] for c in cands])
    t_xy = proj.forward([t["lat"] for t in truth], [t["lon"] for t in truth])
    free = set(range(len(truth)))
    pairs, fps = [], []
    for ci in sorted(range(len(cands)), key=lambda i: -cands[i].get("score", 0)):
        best, best_d = None, radius_m + 1
        for ti in free:
            d = float(np.hypot(*(c_xy[ci] - t_xy[ti])))
            if d <= radius_m and d < best_d:
                best, best_d = ti, d
        if best is None:
            fps.append(ci)
        else:
            free.discard(best)
            pairs.append((ci, best, best_d))
    return pairs, fps, sorted(free)


def evaluate(candidates: list[dict], truth: list[dict], radius_m: float = 40.0, thresholds: list[float] | None = None) -> dict:
    if not truth:
        return {"error": "aucun emplacement réel fourni"}
    pts = candidates + truth
    proj = Projection(float(np.mean([p["lat"] for p in pts])), float(np.mean([p["lon"] for p in pts])))
    scores = sorted({c.get("score", 0) for c in candidates})
    ths = thresholds or sorted({0.0, *scores})
    rows = []
    for t in ths:
        kept = [c for c in candidates if c.get("score", 0) >= t]
        pairs, fps, missed = _match(kept, truth, radius_m, proj)
        tp, fp, fn = len(pairs), len(fps), len(missed)
        prec = tp / (tp + fp) if tp + fp else None
        rec = tp / len(truth)
        f1 = 2 * prec * rec / (prec + rec) if prec and rec else 0.0
        rows.append({"threshold": round(float(t), 3), "candidates": len(kept), "tp": tp, "fp": fp, "fn": fn,
                     "precision": None if prec is None else round(prec, 3), "recall": round(rec, 3), "f1": round(f1, 3)})
    best = max(rows, key=lambda r: (r["f1"], -r["fp"]))
    kept = [c for c in candidates if c.get("score", 0) >= best["threshold"]]
    _, fps, missed = _match(kept, truth, radius_m, proj)
    return {
        "truth": len(truth),
        "radius_m": radius_m,
        "results": rows,
        "best": best,
        "false_positives": [kept[i] for i in fps],
        "missed": [truth[i] for i in missed],
    }
