from __future__ import annotations

import re
import unicodedata

NUM_WORDS = {"un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10}
N = r"(\d+|un|une|deux|trois|quatre|cinq|six|sept|huit|neuf|dix)"


def _norm(text: str) -> str:
    t = unicodedata.normalize("NFD", text.lower())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    return re.sub(r"\s+", " ", t.replace("’", "'")).strip()


def _num(tok: str) -> int:
    return int(tok) if tok.isdigit() else NUM_WORDS[tok]


def parse(question: str) -> dict:
    t = _norm(question)
    events: list[dict] = []
    params: dict = {}
    understood: list[str] = []
    needs: list[str] = []

    def hit(pattern: str):
        return re.search(pattern, t)

    m = hit(rf"{N} camions? (?:de plus|en plus|supplementaires?)") or hit(rf"(?:ajout\w*|rajout\w*|achet\w*|louer?|louons) {N} camions?")
    if m:
        k = _num(m.group(1))
        events.append({"kind": "more_trucks", "value": k})
        understood.append(f"{k} camion(s) de plus")
    m = hit(rf"{N} camions? (?:en panne|tombent? en panne|sont en panne|immobilises?)")
    if m:
        k = _num(m.group(1))
        events.append({"kind": "truck_breakdown", "value": k})
        understood.append(f"{k} camion(s) en panne")
    elif hit(r"camion en panne|panne de camion"):
        events.append({"kind": "truck_breakdown", "value": 1})
        understood.append("1 camion en panne")
    if hit(r"saison des pluies|pluies?|hivernage|inondations?|orages?"):
        events.append({"kind": "rain_season"})
        understood.append("saison des pluies")
    m = hit(r"budget[^0-9%]{0,30}?(?:reduit|reduction|baisse|coupe|diminue|en baisse)[^0-9%]{0,15}?(\d+) ?%") or hit(r"(?:reduction|baisse|coupe) du budget (?:de )?(\d+) ?%")
    if m:
        v = int(m.group(1)) / 100
        events.append({"kind": "budget_cut", "value": v})
        understood.append(f"budget réduit de {m.group(1)} %")
    m = hit(r"abonnements?[^0-9%]{0,25}?(?:baisse\w*|diminu\w*|chute\w*|recul\w*)[^0-9%]{0,12}?(\d+) ?%")
    if m:
        events.append({"kind": "subscription_drop", "value": int(m.group(1)) / 100})
        understood.append(f"abonnements en baisse de {m.group(1)} %")
    if hit(r"nouveau quartier|nouvelle zone|extension de la ville"):
        needs.append("emplacement du nouveau quartier")

    m = hit(r"(?:passage|collecte|ramassage|tournee)s? tous les (\d+) jours?") or hit(r"frequence de (\d+) jours?")
    if m:
        params["frequency_days"] = int(m.group(1))
        understood.append(f"passage tous les {m.group(1)} jours")
    m = hit(rf"{N} tricycles?")
    if m and "camion" not in m.group(0):
        params["tricycles"] = _num(m.group(1))
        understood.append(f"{params['tricycles']} tricycle(s)")
    m = hit(rf"{N} pre-?collecteurs?")
    if m:
        params["precollectors"] = _num(m.group(1))
        understood.append(f"{params['precollectors']} pré-collecteurs")
    m = hit(r"(?:taux d'abonnement|abonnes?)[^0-9%]{0,15}?(\d+) ?%")
    if m:
        params["subscription_rate"] = int(m.group(1)) / 100
        understood.append(f"{m.group(1)} % d'abonnés")
    m = hit(r"budget (?:de |a |=)?\s*(\d[\d ]*(?:[.,]\d+)?) ?(millions?|m\b|fcfa)")
    if m and "budget_cut" not in [e["kind"] for e in events]:
        raw = float(m.group(1).replace(" ", "").replace(",", "."))
        amount = raw * 1_000_000 if m.group(2).startswith("m") else raw
        params["budget_month"] = amount
        understood.append(f"budget de {int(amount):,} FCFA".replace(",", " "))
    m = hit(r"(?:compost\w*|valoris\w*)[^0-9%]{0,25}?(\d+) ?%")
    if m:
        params["organic_recovery"] = int(m.group(1)) / 100
        understood.append(f"{m.group(1)} % des déchets organiques valorisés")
    m = hit(r"(?:laabal|brigade)[^0-9]{0,25}?(\d+) ?(?:kg|tonnes?|t)\b")
    if m:
        v = float(m.group(1))
        params["laabal_kg_day"] = v * 1000 if "t" in m.group(0)[-7:] and "kg" not in m.group(0)[-7:] else v
        understood.append("capacité de la brigade modifiée")

    return {"events": events, "params": params, "understood": understood, "needs": needs, "recognized": bool(events or params)}
