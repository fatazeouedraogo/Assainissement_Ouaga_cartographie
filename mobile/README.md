# OuagaClean — application mobile

Application Flutter de signalement et de suivi des dépotoirs de Ouagadougou.
Elle parle uniquement à l'API Express (`api/`), qui appelle le moteur FastAPI (`moteur/`).

## Mise en place

Dans ce dossier, avec le partage de connexion du téléphone pour le premier lancement :

```powershell
Remove-Item -Recurse -Force lib -ErrorAction SilentlyContinue
# copier ici lib/, assets/, test/, tool/, pubspec.yaml, analysis_options.yaml de l'archive
powershell -ExecutionPolicy Bypass -File tool\setup.ps1
flutter run --dart-define=API_BASE=http://IP_DU_PC:3000
```

`IP_DU_PC` : adresse IPv4 donnée par `ipconfig`. Le téléphone et le PC doivent être sur le même réseau.
Émulateur Android : `http://10.0.2.2:3000`. L'adresse peut aussi se changer dans l'écran de connexion.

## Comptes de démonstration (après `npm run seed` dans `api/`)

Mot de passe `demo-2026` : `+22670000001` administrateur, `+22670000002` vérificateur, `+22670000003` agent.

## Ce que fait l'application

- Signaler : photo, GPS avec mini-carte, mémo vocal (60 s, sans transcription), taille, type, zone inondable ; envoi différé si le réseau manque.
- Carte : dépotoirs par statut, filtres, fiche avec actions du vérificateur, candidats satellite, export GeoJSON.
- Impact : suivi de chaque signalement en quatre étapes, points, classement, chiffres de la ville.
- Vérifier (vérificateur, administrateur) : valider ou rejeter, candidats satellite et précision mesurée.
- Plan (vérificateur, administrateur), en quatre onglets :
  - Réglages : paramètres du moteur et imprévus (crash-test).
  - Résultat : indicateurs, tournées animées, vue des pré-collecteurs, note de décision en PDF.
  - Courbes : évolution sur l'horizon de simulation (`simulation.series`), avec marge d'incertitude.
  - Comparer : scénario A (réglages actuels) contre B (variante), calculés par le moteur.
- Compte : notifications, mes signalements, test de connexion à l'API et au moteur.

## Communes et quartiers

Touchez le nom de la ville en haut : liste des communes, puis classement des quartiers (à traiter, nettoyés, part nettoyée). Ces écrans lisent `GET /api/admin/communes` et `GET /api/admin/communes/:id/quartiers`, fournis par l'add-on `ouagaclean-api-communes-quartiers.zip` (à dézipper dans `api/`). Sans lui, l'écran l'indique clairement.

## Langues

Français et anglais pour l'écran Signaler, les onglets et la synchronisation. Le mooré et le dioula sont **vides** : les textes doivent être écrits ou validés par des locuteurs dans `tool/traductions_a_valider.csv`, puis `python tool/i18n_csv_to_json.py`. Une case vide affiche le français. Choix de la langue : Mon compte.

## Mémo vocal

Enregistrement `.m4a` joint au signalement, envoyé sur `POST /api/voice` après le signalement (voir `AJOUT-OUAGACLEAN.md` côté API). Le vérificateur l'écoute dans la fiche du dépotoir. Permission micro et `minSdk 23` : `tool/setup.ps1` les ajoute.

## Données et licences

Fond de carte © contributeurs OpenStreetMap (ODbL). Licence du code : MIT.

## Routes utilisées par les écrans ajoutés

| Écran | Route |
|---|---|
| Courbes | `simulation.series` dans la réponse de `POST /api/plan` |
| Comparer | `POST /api/scenarios/compare` |
| Pré-collecteurs | `POST /api/insights/precollectors` |
| Note PDF | `POST /api/insights/report.pdf` |

La lecture des réponses est regroupée dans `lib/core/analytics.dart` : si le format d'une réponse diffère, c'est le seul fichier à ajuster.
