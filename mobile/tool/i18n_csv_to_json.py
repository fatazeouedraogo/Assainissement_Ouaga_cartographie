"""Transforme tool/traductions_a_valider.csv (rempli par des locuteurs) en assets/i18n/*.json.
Usage : python tool/i18n_csv_to_json.py
Une case vide reste vide : l'application affiche alors le français."""
import csv, json, os

here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(here, 'traductions_a_valider.csv')
out = os.path.join(os.path.dirname(here), 'assets', 'i18n')
cols = {'francais': 'fr', 'anglais': 'en', 'moore': 'mos', 'dioula': 'dyu'}
data = {c: {} for c in cols.values()}
with open(src, encoding='utf-8-sig', newline='') as f:
    for row in csv.DictReader(f):
        for col, code in cols.items():
            data[code][row['cle']] = (row.get(col) or '').strip()
for code, d in data.items():
    with open(os.path.join(out, code + '.json'), 'w', encoding='utf8') as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print(f'{code}: {sum(1 for v in d.values() if v)}/{len(d)} textes remplis')
