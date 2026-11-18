# OuagaClean — fichier de reprise (à donner à une autre IA)

Dernière mise à jour : 18/11/2026. Utilisateur : Fatao (GitHub `fatazeouedraogo`), licence en informatique terminée à BIT, Master 1 à l'UJKZ. Écrit en français familier, veut du code prêt à l'emploi, peu de théorie, est pressé. Veut que ce fichier soit mis à jour à chaque livraison.

## Consigne pour l'IA qui reprend
Réponds en français simple. Donne des commandes à copier, une étape à la fois. Ne promets jamais un résultat non mesuré. Dis clairement ce qui est testé et ce qui ne l'est pas. Ne prétends pas avoir exécuté du code que tu n'as pas exécuté. Aucune donnée simulée dans l'app : les maquettes ne servent que d'inspiration, tout doit venir du vrai backend. Évite les commentaires de code qui sentent l'IA.

## Le projet
Hackathon (finale), thème Open Source, défi « Assainissement de Ouagadougou » : signaler les dépotoirs, les valider, planifier la collecte (camions, tricycles, pré-collecteurs), simuler des scénarios. App : **OuagaClean**. Dépôt : https://github.com/fatazeouedraogo/Assainissement_Ouaga_cartographie (`moteur`, `api`, `mobile`, branche `main`).

- `moteur/` : FastAPI (Python 3.11). Placement équitable, tournées OR-Tools, simulation multi-agents, priorité sanitaire, Pareto, recommandation, carte de risque, satellite par règles, CLIP optionnel.
- `api/` : Express + PostgreSQL/PostGIS. Auth JWT, signalements, dépotoirs, plan (appelle le moteur), candidats satellite, notifications, capteurs, page publique.
- `mobile/` : Flutter, parle uniquement à l'API Express (qui appelle le moteur avec `ENGINE_API_KEY`).
- `admin/` : à venir.

## État réel (vérifié ou non)
Vérifié par l'utilisateur : moteur (`pytest` 20 passed, uvicorn port 8000), `npm install` de l'API, météo Open-Meteo, push GitHub. PostGIS : l'utilisateur dit l'avoir installé (18/11/2026), **non vérifié** (tester `SELECT PostGIS_Version();`). API jamais lancée à ce jour. Flutter : jamais exécuté sur téléphone avec l'API.

Non vérifié, écrit le 18/11/2026 sans SDK Flutter ni Dart : les écrans Courbes, Comparer, Pré-collecteurs, PDF, Communes, Quartiers, et le mémo vocal / les langues (voir plus bas). Première chose à faire : `flutter pub get` puis `flutter analyze`, corriger les erreurs.

Peu d'IA entraînée : optimisation, simulation, règles. CLIP branché mais jamais exécuté. Ne pas dire « IA » partout devant le jury.

## Environnement (Windows 10)
- Disque C: presque plein : éviter les gros téléchargements.
- PostgreSQL 17 et 18 installés, le 18 sur le port 5432, mot de passe `admin123`, base `ouaga`. `DATABASE_URL=postgres://postgres:admin123@localhost:5432/ouaga` dans `api/.env`.
- Le réseau habituel bloque GitHub, Google Maven, parfois le DNS : utiliser le partage de connexion du téléphone. Test : `Test-NetConnection github.com -Port 443`.
- Téléphone de test : Samsung SM M135FU, adb `RZ8T70YTSXL`. Sur un vrai téléphone, utiliser l'IP du PC (pas `10.0.2.2`).
- `.venv` et `node_modules` hors dépôt. Git : si Vim s'ouvre, `Esc` puis `:wq`.

## Commandes pour tout lancer
```powershell
# moteur
cd C:\Users\ABCD\Ouaga_Assainissement\moteur
.\.venv\Scripts\Activate.ps1
uvicorn app.main:app --reload --port 8000

# API
cd C:\Users\ABCD\Ouaga_Assainissement\api
copy .env.example .env   # DATABASE_URL, JWT_SECRET, ENGINE_URL=http://localhost:8000, ENGINE_API_KEY
npm install
npm run migrate
npm run seed             # mot de passe demo-2026 : +22670000001 admin, +22670000002 vérificateur, +22670000003 agent
npm run dev              # port 3000

# mobile
cd C:\Users\ABCD\Ouaga_Assainissement\mobile
flutter pub get
flutter analyze
flutter run --dart-define=API_BASE=http://IP_DU_PC:3000
```

## API Express existante
Auth : `POST /api/auth/login|register`, `GET /api/auth/me`. Signalements : `POST /api/reports` (multipart), `GET /api/reports/mine`. Dépotoirs : `GET /api/dumps`, `POST /api/dumps/:id/verify|reject|schedule|clean`, `GET /api/dumps/priorities`. Plan : `GET /api/plan/controls`, `POST /api/plan`, `GET /api/plan/latest`. Satellite : `/api/candidates...`. Public : `/api/public/...`. Notifications. Capteurs `/api/iot`. Insights : `/api/insights/precollectors`, `/api/insights/report.pdf`. Scénarios : `/api/scenarios/compare`.

## Ajouts du 18/11/2026
**App mobile** (`ouagaclean-mobile-flutter.zip`) :
- Plan en 4 onglets : Réglages, Résultat, Courbes (`simulation.series`), Comparer (A contre B).
- Vue des pré-collecteurs et note de décision PDF depuis l'onglet Résultat.
- Touche sur « Ouagadougou » en haut : liste des communes, puis classement des quartiers.
- Toute la lecture des réponses est dans `lib/core/analytics.dart` (formats déduits de ce fichier, **à confirmer** avec les vrais JSON de l'API).

**Backend** (`ouagaclean-api-communes-quartiers.zip`, se dézippe dans `api/`, voir `api/AJOUT-OUAGACLEAN.md`) :
- L'API est en **ES modules** (`import`, `"type": "module"`), migrations dans `db/migrations/` appliquées toutes seules au démarrage (`npm run dev` ou `npm run migrate`). Ajout : `005` (régions, provinces, communes, quartiers), `006` (mairies, `users.commune_id`), `007` (mémos vocaux).
- Routes `/api/admin/...` : lecture des régions, provinces, communes, mairies, quartiers avec compteurs de dépotoirs ; création par l'administrateur ; `GET /api/admin/users` ; `PUT /api/admin/users/:id/commune` pour affecter un compte.
- `scripts/admin-import.js` : import de vraies limites GeoJSON. `scripts/smoke-test.js` : teste les routes que l'app appelle.
- Seul fichier existant modifié : `src/app.js` (3 imports, 3 `app.use`).
- Découpage officiel depuis juillet 2025 : 17 régions, 47 provinces, 350 départements. Saisir les noms officiels actuels, ne rien inventer.
- Pas encore fait : filtrer `/api/dumps`, `/api/plan` et les signalements par commune ; l'app n'applique pas encore la commune de l'utilisateur.

**Testé le 18/11/2026 sur le vrai code `api/`** (PostgreSQL 16 + PostGIS 3.4, Node 22, dans un bac à sable) : migrations sur base vierge et rejouées ; création région/province/commune/mairie ; import GeoJSON ; compteurs par quartier ; affectation d'un compte ; envoi, remplacement et écoute d'un mémo vocal ; refus (autre compte, fichier trop lourd, mauvais type, signalement absent) ; tests unitaires du projet (14/14). **Non testé** : moteur FastAPI (donc plan, comparaison, pré-collecteurs, PDF) et Flutter. Les tests d'intégration du projet donnent 6 échecs sur 18, **identiques sur l'API d'origine sans mes ajouts** : le signalement sort « flagged » au lieu de « accepted » parce que l'analyse de photo demande le moteur. À relancer avec le moteur actif : `npm run test:integration` (base `ouaga_test` à créer).

**Bogue corrigé dans l'app** : l'onglet Comparer envoyait `scenarios` ; l'API attend `inline` et des noms de 2 caractères minimum (« Scénario A », « Scénario B »).

## Voix et langues (ajoutés, non compilés)
Côté app : écrit le 18/11/2026 sans SDK Flutter ni Dart, **jamais compilé ni exécuté**. Côté backend : testé (voir plus haut).

**Mémo vocal**
- App : `lib/features/voice_note.dart` (enregistrement AAC `.m4a`, 60 s max, réécoute, suppression). Aucune transcription automatique. Paquets ajoutés : `record`, `audioplayers`. Permission `RECORD_AUDIO` et `minSdk 23` ajoutés par `tool/setup.ps1`.
- Envoi : le signalement part d'abord, puis le mémo sur `POST /api/voice` (`client_id`, `duration_s`, `audio`). Hors ligne, `lib/core/outbox.dart` garde photo et mémo et les envoie dans cet ordre ; si seul le mémo échoue, il reste en file seul.
- Backend : migration `007_report_audio.sql`, `src/routes/report-audio.js` (`POST /api/voice`, `GET /api/voice/by-dump/:dumpId` pour vérificateur et admin). Fichiers dans `uploads/audio/`, servis par `/uploads/` sans protection par la connexion (nom aléatoire).
- Vérificateur : la fiche d'un dépotoir (`dump_sheet.dart`) affiche les mémos et permet de les écouter.

**Langues**
- `lib/core/i18n.dart` lit `assets/i18n/{fr,en,mos,dyu}.json` ; clé vide ou absente = français. Choix de la langue dans Mon compte.
- Français et anglais complets pour l'écran Signaler, les onglets et la synchronisation (72 clés). **Mooré et dioula : fichiers vides**, rien d'inventé. À remplir par des locuteurs dans `tool/traductions_a_valider.csv`, puis `python tool/i18n_csv_to_json.py`.
- Les autres écrans (Carte, Impact, Vérifier, Plan, Communes, Compte, Connexion) sont encore en français en dur. `python tool/extract_strings.py` les liste.
- Le mémo vocal sert à dire le signalement dans sa langue : il n'est pas traduit ni transcrit.

**Test de toutes les routes** : `node scripts/smoke-test.js http://localhost:3000` (dans `api/`), enregistre les vraies réponses dans `smoke-output/`.

## Reste à faire, par priorité
1. Vérifier PostGIS, `npm run migrate`, `seed`, `dev` (moteur lancé), puis `node scripts/smoke-test.js http://localhost:3000`, login depuis l'app.
2. Dézipper l'add-on dans `api/`, relancer `npm run dev` (les migrations 005 à 007 s'appliquent seules), importer une vraie base région/province/commune/mairie et les secteurs.
3. `flutter pub get` (nouveaux paquets `record`, `audioplayers`), `flutter analyze`, corriger, tester sur téléphone (micro compris).
4. Filtrage par commune dans l'API et l'app (affectation des comptes).
5. Mesurer la détection satellite (vraie image, 15 à 20 dépotoirs réels et autant de points sans dépotoir). Premier dépotoir connu : 12.328877, -1.458722.
6. Démo de 5 minutes avec données préchargées ; mode « saison des pluies » activable à la main.
7. Contribution OSM, OSRM, textes mooré/dioula validés par des locuteurs et traduction des autres écrans, transcription des mémos vocaux, capteurs dans le plan, CLIP si le disque le permet.
8. Ordre de mission PDF/SMS, détail des tournées par benne (chauffeur, horaires : absents du plan), mode sombre.
9. Licences : aucune image Google ou Esri dans le dépôt ni dans OpenStreetMap.

## Prompt à coller dans le nouveau chat
« Je continue le projet OuagaClean (hackathon, assainissement de Ouagadougou). Lis le fichier REPRISE-OUAGACLEAN.md joint. Réponds en français simple, une étape à la fois, avec des commandes à copier. Ne prétends pas avoir testé ce que tu n'as pas exécuté. Commence par me demander la sortie de `flutter analyze` dans le dossier mobile. »
