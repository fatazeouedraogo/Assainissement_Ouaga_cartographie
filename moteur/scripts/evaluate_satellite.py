"""Mesure la précision de la détection satellite sur des dépotoirs connus.

  python scripts/evaluate_satellite.py --image quartier.png --bbox 12.36,-1.53,12.37,-1.52 \
      --truth depotoirs.csv [--masks masques.json] [--risk risque.json] [--radius 40]

depotoirs.csv : colonnes lat,lon. masques.json : sortie de fetch_osm_masks.py.
"""
import argparse
import csv
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app import evaluation, satellite  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--bbox", required=True, help="sud,ouest,nord,est")
    ap.add_argument("--truth", required=True)
    ap.add_argument("--masks")
    ap.add_argument("--risk")
    ap.add_argument("--radius", type=float, default=40.0)
    ap.add_argument("--block", type=int, default=12)
    a = ap.parse_args()

    bbox = tuple(float(x) for x in a.bbox.split(","))
    truth = [{"lat": float(r["lat"]), "lon": float(r["lon"])} for r in csv.DictReader(open(a.truth, encoding="utf-8"))]
    masks = json.load(open(a.masks)) if a.masks else None
    risk = json.load(open(a.risk)) if a.risk else None

    cands, stats = satellite.find_candidates(
        open(a.image, "rb").read(), bbox, block_px=a.block, top=100, masks=masks, risk_cells=risk, min_score=0.0, return_stats=True,
    )
    rep = evaluation.evaluate(cands, truth, a.radius)
    print(f"Blocs analysés : {stats['blocks']}, exclus par masques : {stats['excluded']}")
    print(f"Dépotoirs réels : {rep['truth']}, rayon de correspondance : {a.radius:.0f} m\n")
    print("seuil   candidats  trouvés  faux  manqués  précision  rappel")
    for r in rep["results"][:: max(1, len(rep["results"]) // 12)]:
        p = "—" if r["precision"] is None else f"{r['precision']:.0%}"
        print(f"{r['threshold']:5.2f}  {r['candidates']:9d}  {r['tp']:7d}  {r['fp']:4d}  {r['fn']:7d}  {p:>9}  {r['recall']:.0%}")
    b = rep["best"]
    print(f"\nMeilleur compromis : seuil {b['threshold']} → {b['tp']} dépotoirs retrouvés sur {rep['truth']}, {b['fp']} faux positifs (précision {b['precision']}, rappel {b['recall']}).")
    json.dump(rep, open("evaluation_satellite.json", "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
