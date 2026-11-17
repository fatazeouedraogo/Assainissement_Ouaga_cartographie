# Moteur Ouaga Assainissement (FastAPI)

Service de calcul de l'outil d'aide à la décision : placement des points de regroupement, tournées de collecte, simulation multi-agents, scores de priorité sanitaire, analyse des photos de signalement. Il est appelé par l'API Express et ne stocke rien.

## Lancer

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

Docs interactives : http://localhost:8000/docs

Avec Docker : `docker build -t moteur . && docker run -p 8000:8000 --env-file .env moteur`

Tests : `pip install -r requirements-dev.txt && pytest -q`

## Variables d'environnement

| Variable | Rôle |
|---|---|
| `ENGINE_API_KEY` | Si définie, exigée dans l'en-tête `X-Engine-Key` |
| `OSRM_URL` | Serveur OSRM pour les distances routières réelles. Sans lui, distance à vol d'oiseau × `detour_factor` |
| `USE_CLIP` | `1` active la vérification des photos par CLIP (installer `requirements-ai.txt`) |

## Ce que fait chaque module

| Fichier | Contenu |
|---|---|
| `placement.py` | k-means pondéré en mètres. Le nombre de points augmente jusqu'à la couverture visée et au respect de la capacité des conteneurs. `equity_boost` surpondère les ménages des couronnes périphériques. Les points se calent sur les dépotoirs existants à moins de 80 m |
| `routing.py` | Tournées avec OR-Tools : capacité, durée de rotation, rotations multiples, départ du garage puis de la décharge, abandon pénalisé. Heuristique plus proche voisin + 2-opt si OR-Tools est absent |
| `planner.py` | Répartit les points en groupes de jours selon la fréquence. Flotte mixte : les points à accès étroit sont servis par des tricycles qui déposent à un point de transfert, que les camions vident ensuite |
| `simulation.py` | Ménages, pré-collecteurs, points, camions (pannes), brigade Laabal, mairie (budget). Réplications aléatoires, bandes 5 % à 95 % |
| `scenarios.py` | Événements (panne, pluies, nouveau quartier, baisse de budget), comparaison de scénarios, analyse de sensibilité par élasticité |
| `priority.py` | Score 0 à 100 expliqué par composante : taille, ancienneté, proximité des caniveaux, proximité des écoles, marchés et centres de santé |
| `assistant.py` | Comprend une question en français (« et si on avait 3 camions de plus pendant la saison des pluies ? ») et la traduit en événements et paramètres, sans modèle de langage externe |
| `decision.py` | Compromis coût, fuites, CO₂ et équité (front de Pareto), recommandation de la meilleure réponse à un aléa, calibration d'un paramètre sur une valeur observée |
| `predict.py` | Carte de risque des futurs dépotoirs : historique et récidives, densité de ménages, marchés, eau. Indicatif |
| `satellite.py` | Repère des zones suspectes sur une image aérienne RVB (texture, végétation, luminosité) : des candidats à vérifier sur le terrain, pas des certitudes |
| `scripts/kit_commune.py` | Prépare une autre commune en une commande (bâtiments OSM, instructions) |
| `photo.py` | Qualité (flou, luminosité), empreinte perceptuelle pour détecter les photos réutilisées, CLIP si activé |

## Points d'attention

- Les paramètres par défaut (production de déchets par personne, coûts, capacités) sont des hypothèses de départ. Ils doivent être fixés avec la mairie, c'est pourquoi tout passe par `Params`.
- Sans CLIP, l'analyse de contenu est une heuristique non fiable : la réponse porte `reliable: false` et l'API Express ne rejette alors que sur la qualité de l'image.
- La distance routière réelle demande un serveur OSRM chargé avec l'extrait OpenStreetMap du Burkina Faso.

## Endpoints

| Méthode | Route | Rôle |
|---|---|---|
| GET | `/health` | État du service |
| GET | `/v1/controls` | Paramètres modifiables avec bornes, pour construire l'interface |
| POST | `/v1/plan` | Points de regroupement et tournées |
| POST | `/v1/simulate` | Plan et simulation avec intervalles de confiance |
| POST | `/v1/scenarios/compare` | Comparaison côte à côte de scénarios |
| POST | `/v1/sensitivity` | Paramètres classés par impact |
| POST | `/v1/priority/score` | Score de priorité sanitaire des dépotoirs |
| POST | `/v1/photo/analyze` | Analyse d'une photo (multipart) |
| POST | `/v1/assistant/parse` | Question en français vers événements et paramètres |
| POST | `/v1/predict/risk` | Zones à risque de futurs dépotoirs |
| POST | `/v1/pareto` | Compromis coût, fuites, CO₂, équité |
| POST | `/v1/recommend` | Meilleure réponse à un aléa |
| POST | `/v1/calibrate` | Calage d'un paramètre sur une valeur observée |
| POST | `/v1/satellite/candidates` | Candidats depuis une image aérienne (multipart) |

Les indicateurs de valorisation (compostage, plastique), d'exposition de la population et de prix d'équilibre de l'abonnement sont inclus dans les résultats de `/v1/plan` et `/v1/simulate`. Les prix de revente sont des hypothèses à confirmer.
