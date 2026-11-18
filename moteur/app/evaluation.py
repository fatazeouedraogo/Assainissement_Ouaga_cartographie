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


def threshold_sweep(positives: list[float], negatives: list[float]) -> dict:
    """Seuils de vraisemblance de déchets : positives = photos de dépotoirs, negatives = autres photos."""
    if not positives or not negatives:
        return {"error": "il faut des photos des deux classes"}
    cuts = sorted({0.0, *positives, *negatives})
    rows = []
    for t in cuts:
        tp = sum(1 for v in positives if v >= t)
        fn = len(positives) - tp
        fp = sum(1 for v in negatives if v >= t)
        tn = len(negatives) - fp
        prec = tp / (tp + fp) if tp + fp else None
        rec = tp / len(positives)
        f1 = 2 * prec * rec / (prec + rec) if prec and rec else 0.0
        rows.append({"threshold": round(t, 3), "tp": tp, "fn": fn, "fp": fp, "tn": tn, "precision": None if prec is None else round(prec, 3), "recall": round(rec, 3), "f1": round(f1, 3)})
    best_f1 = max(rows, key=lambda r: (r["f1"], r["threshold"]))
    safe = [r for r in rows if r["recall"] >= 0.95]
    safest = max(safe, key=lambda r: r["threshold"]) if safe else None
    return {"results": rows, "best_f1": best_f1, "keep_95_percent_of_dumps": safest}
