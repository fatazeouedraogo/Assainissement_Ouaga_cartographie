"""Liste les textes français écrits en dur dans lib/ (Text, labelText, hintText, label, title).
Usage : python tool/extract_strings.py > tool/textes_en_dur.csv
Sert à repérer ce qu'il reste à passer dans assets/i18n/fr.json."""
import csv, os, re, sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib')
pat = re.compile(r"(?:Text\(|labelText:|hintText:|label:|title:)\s*(?:const\s+Text\()?\s*'((?:[^'\\]|\\.)*)'")
w = csv.writer(sys.stdout)
w.writerow(['fichier', 'ligne', 'texte'])
for d, _, files in os.walk(root):
    for name in sorted(files):
        if not name.endswith('.dart'):
            continue
        p = os.path.join(d, name)
        for i, line in enumerate(open(p, encoding='utf8'), 1):
            for m in pat.finditer(line):
                t = m.group(1)
                if re.search(r'[A-Za-zÀ-ÿ]{3}', t) and '$' not in t[:1]:
                    w.writerow([os.path.relpath(p, root), i, t])
