from .schemas import Params

_D = Params()

CONTROLS = [
    ("trucks", "Camions", "camions", 0, 30, 1, "flotte"),
    ("truck_capacity_kg", "Capacité d'un camion", "kg", 2000, 20000, 500, "flotte"),
    ("trips_per_day", "Rotations par jour", "trajets", 1, 4, 1, "flotte"),
    ("tricycles", "Tricycles de collecte", "tricycles", 0, 60, 1, "flotte"),
    ("frequency_days", "Passage tous les", "jours", 1, 7, 1, "organisation"),
    ("budget_month", "Budget mensuel", "FCFA", 1_000_000, 30_000_000, 100_000, "organisation"),
    ("laabal_kg_day", "Nettoyage brigade Laabal", "kg/jour", 0, 6000, 100, "organisation"),
    ("max_walk_m", "Distance de marche max", "m", 100, 800, 25, "points"),
    ("target_coverage", "Couverture visée", "", 0.5, 1.0, 0.01, "points"),
    ("equity_boost", "Priorité aux périphéries", "", 0, 3, 0.1, "points"),
    ("subscription_rate", "Ménages abonnés", "", 0, 1, 0.01, "ménages"),
    ("precollectors", "Pré-collecteurs", "personnes", 0, 300, 5, "ménages"),
    ("waste_kg_per_person_day", "Déchets par personne", "kg/jour", 0.2, 1.0, 0.01, "ménages"),
    ("organic_recovery", "Déchets organiques valorisés", "", 0, 1, 0.05, "valorisation"),
    ("plastic_recovery", "Plastiques valorisés", "", 0, 1, 0.05, "valorisation"),
    ("breakdown_prob", "Risque de panne par jour", "", 0, 0.3, 0.01, "aléas"),
]


def controls() -> list[dict]:
    out = []
    for key, label, unit, lo, hi, step, group in CONTROLS:
        out.append(
            {
                "key": key,
                "label": label,
                "unit": unit,
                "min": lo,
                "max": hi,
                "step": step,
                "default": getattr(_D, key),
                "group": group,
            }
        )
    return out
