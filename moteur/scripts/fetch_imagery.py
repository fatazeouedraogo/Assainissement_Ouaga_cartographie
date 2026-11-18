"""Assemble une image d'un quartier à partir de tuiles XYZ que vous avez le droit d'utiliser.

  python scripts/fetch_imagery.py --bbox 12.36,-1.53,12.37,-1.52 --zoom 19 \
      --tiles "https://VOTRE_SERVEUR/{z}/{x}/{y}.jpg" --out quartier.png

Vérifiez la licence de la source (imagerie de drone, Mapbox avec votre clé, mosaïque OpenAerialMap...).
La commande affiche l'emprise à passer ensuite à evaluate_satellite.py.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.imagery import fetch_mosaic  # noqa: E402

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--bbox", required=True, help="sud,ouest,nord,est")
    ap.add_argument("--zoom", type=int, default=18)
    ap.add_argument("--tiles", required=True)
    ap.add_argument("--out", default="quartier.png")
    a = ap.parse_args()
    bbox = tuple(float(x) for x in a.bbox.split(","))
    img = fetch_mosaic(bbox, a.zoom, a.tiles)
    img.save(a.out)
    print(f"{a.out} : {img.size[0]}x{img.size[1]} px, emprise {a.bbox}")
