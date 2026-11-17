# API REST Ouaga Assainissement (Node.js, Express, PostgreSQL/PostGIS)

Reçoit les signalements de dépotoirs, les valide, les fusionne en dépotoirs, calcule la confiance et la priorité, et déclenche les plans et simulations du moteur FastAPI.

## Démarrage rapide

Avec Docker (API, PostGIS et moteur ensemble, `moteur/` doit se trouver à côté de ce dossier) :

```bash
export JWT_SECRET="$(openssl rand -hex 32)"
docker compose up --build
docker compose exec api node scripts/seed-demo.js
```

Sans Docker : PostgreSQL 14+ avec PostGIS, Node 20+, le moteur sur le port 8000.

```bash
cp .env.example .env
npm install
npm run migrate
npm run seed
npm run dev
```

Le seed crée trois comptes (`+22670000001` admin, `+22670000002` vérificateur, `+22670000003` agent, mot de passe `demo-2026`) et des bâtiments **synthétiques**. En production, importez les vrais bâtiments (Open Buildings) avec `POST /api/buildings/bulk`, et les lieux sensibles OpenStreetMap avec `scripts/import_osm.py` du moteur.

Tests : `npm test` (règles métier) puis `npm run test:integration` (PostGIS et moteur requis, base `ouaga_test`).

## Règles de validation d'un signalement

| Cas | Résultat |
|---|---|
| Position hors de Ouagadougou, photo absente ou illisible | Rejeté |
| Même auteur à moins de 30 m dans les dernières 24 h | Rejeté (doublon) |
| Même photo (empreinte perceptuelle) déjà utilisée ailleurs, ou par le même auteur | Rejeté (photo réutilisée) |
| GPS imprécis, photo floue ou sombre, contenu douteux, photo proche d'un autre auteur, déplacement impossible | Accepté avec drapeaux, crédibilité réduite |
| Autre auteur à moins de 30 m | Fusionné dans le dépotoir existant |

La confiance d'un dépotoir combine les crédibilités des auteurs distincts (probabilité qu'au moins un ait raison). À 0,9 de confiance avec 3 auteurs, il passe automatiquement en « vérifié ». Les seuils se règlent via `PUT /api/settings/thresholds`. Un signalement à moins de 30 m d'un dépotoir nettoyé crée un nouveau dépotoir marqué récidive.

## Routes principales

| Méthode | Route | Accès |
|---|---|---|
| POST | `/api/auth/register`, `/api/auth/login` | public |
| GET | `/api/auth/me` | connecté |
| POST | `/api/reports` (multipart : photo, lat, lon, size, waste_type, client_id) | connecté |
| GET | `/api/reports/mine` | connecté |
| GET | `/api/dumps` (GeoJSON, filtres `bbox`, `status`) | connecté |
| GET | `/api/dumps/priorities`, `/api/dumps/:id` | connecté |
| POST | `/api/dumps/:id/verify`, `/reject`, `/schedule`, `/clean` | vérificateur, admin |
| POST | `/api/dumps/recompute-priority` | vérificateur, admin |
| GET | `/api/plan/controls` | vérificateur, admin |
| POST | `/api/plan`, `/api/plan/sensitivity` | vérificateur, admin |
| GET/POST/DELETE | `/api/scenarios`, POST `/api/scenarios/compare` | vérificateur, admin |
| POST | `/api/buildings/bulk`, `/api/poi/bulk` | admin |
| GET/PUT | `/api/settings` (dépôt, décharge, seuils) | admin pour l'écriture |
| GET | `/api/public/overview`, `/hotspots`, `/leaderboard`, `/dumps.geojson` | public |
| GET | `/api/public/maproulette.ndjson` | admin |

| POST | `/api/insights/ask` | vérificateur, admin : question en français, réponse chiffrée |
| POST | `/api/insights/recommend`, `/pareto` | vérificateur, admin : meilleure réponse à un aléa, compromis coût/fuites/équité |
| POST | `/api/insights/calibrate` | admin : calage d'un paramètre sur une valeur observée |
| GET | `/api/insights/risk`, `/weather` | connecté : zones à risque de futurs dépotoirs, prévisions de pluie (Open-Meteo) |
| POST | `/api/insights/report.pdf` | vérificateur, admin : note de décision d'une page |
| GET/POST | `/api/notifications`, `/read` | connecté : notifications d'avancement aux auteurs |
| POST/GET | `/api/iot/sensors`, `/readings`, `/status` | capteurs de remplissage (ESP32, voir `iot/`) |
| POST/GET | `/api/candidates/scan`, `/` | candidats repérés sur image aérienne, à vérifier au sol |
| GET/POST | `/api/subscriptions/price`, `/pay`, `/mine` | abonnement avec paiement Orange/Moov **simulé** |
| GET/POST | `/api/whatsapp/webhook` | signalement par WhatsApp : position, puis photo |
| GET | `/` | tableau de bord public (page web, sans connexion) |

`client_id` est un UUID généré par le mobile : rejouer un envoi hors ligne ne crée jamais de doublon.

## À renseigner avant la démonstration

Le garage et la décharge sont des **valeurs provisoires** (`placeholder`). Chaque plan renvoie `warnings: ["depot_a_renseigner", "decharge_a_renseigner"]` tant qu'ils n'ont pas été fixés avec la mairie via `PUT /api/settings/depot` et `/landfill`.


## Fonctions ajoutées

- **Notifications** : l'auteur d'un signalement est prévenu quand le dépotoir est confirmé, programmé et nettoyé.
- **Météo** : `GET /api/insights/weather` applique la règle « au moins 3 jours à 10 mm, ou un jour à 40 mm » sur 7 jours. L'app propose alors de simuler la saison des pluies.
- **WhatsApp** : définir `WHATSAPP_TOKEN`, `WHATSAPP_PHONE_ID`, `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_APP_SECRET`, puis déclarer `https://votre-domaine/api/whatsapp/webhook` dans Meta for Developers. Sans le secret, tout appel est refusé. Le parcours (position, taille, photo) est testé avec des messages simulés ; le raccordement réel à Meta n'a pas pu être essayé.
- **Capteurs** : créer un capteur (`POST /api/iot/sensors`), recopier le secret affiché dans `iot/esp32_sensor.ino`. Au-delà de 80 % de remplissage, le conteneur est marqué urgent.
- **Candidats satellite** : `POST /api/candidates/scan` (image RVB + emprise) crée des candidats que l'équipe vérifie sur le terrain. L'image est à fournir ; l'API ne télécharge pas d'imagerie.
- **Abonnement** : le paiement Orange/Moov est une **simulation** (référence `SIM-…`). Il faut un contrat avec un opérateur pour de vrais paiements.
- **Autre commune** : démarrer avec `COMMUNE_BBOX=sud,ouest,nord,est` et utiliser `scripts/kit_commune.py` du moteur.
- **Licence** : MIT pour le code. Les données OpenStreetMap restent sous ODbL (voir `DONNEES.md`).
