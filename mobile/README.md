# Ouaga Propre (application mobile Flutter)

Signalement de dépotoirs, carte, priorités sanitaires et simulateur de scénarios pour la mairie. Elle parle uniquement à l'API Express.

## Installation

Prérequis : Flutter 3.27 ou plus récent.

```bash
cd mobile
sh tool/setup.sh        # génère android/ et ios/, ajoute les permissions, lance flutter pub get
flutter run --dart-define=API_BASE=http://10.0.2.2:3000
```

- `10.0.2.2` désigne l'ordinateur depuis l'émulateur Android. Sur un vrai téléphone, utilisez l'adresse IP de l'ordinateur (par exemple `http://192.168.1.10:3000`), ou saisissez-la dans l'écran de connexion (« Adresse du serveur »).
- Le trafic HTTP en clair est autorisé par le script pour le développement. En production, servez l'API en HTTPS et retirez `usesCleartextTraffic`.
- Les polices (Bricolage Grotesque, Hanken Grotesk) sont chargées par `google_fonts` à la première utilisation. Pour un fonctionnement 100 % hors ligne, placez les fichiers dans `assets/fonts` et déclarez-les dans `pubspec.yaml`.

## Ce que contient l'application

| Écran | Rôle |
|---|---|
| Carte | OpenStreetMap, dépotoirs dessinés en tas dont la taille dépend du risque, anneau jaune pour les récidives, filtres par statut |
| Signaler | Photo, position GPS avec précision, taille par pictogrammes, type de déchets. Fonctionne hors réseau : le signalement est conservé dans une base locale puis envoyé automatiquement, sans doublon grâce à un identifiant unique |
| Priorités | Classement par risque sanitaire avec la raison principale |
| Fiche dépotoir | Photos avant et après, décomposition du score, signalements, actions du vérificateur (confirmer, programmer, clôturer avec photo) |
| Simulateur (vérificateur, admin) | Curseurs issus du moteur, aléas (panne, pluies, baisse de budget), résultats avec fourchettes, comparaison à la situation actuelle |
| Assistant | Question libre en français dans le simulateur (« et si on avait 3 camions de plus pendant la saison des pluies ? ») |
| Tournées | Carte animée des camions et tricycles par jour |
| Aide à la décision | Meilleure réponse à un aléa, compromis coût, fuites et équité, note PDF pour le maire, alerte pluies annoncées |
| Couches de carte | Risque de futurs dépotoirs, candidats repérés par satellite et capteurs de remplissage (vérificateur, admin) |
| Moi | Points, badges, tableau de bord de la ville, classement, file d'envoi |

## Langues

Français et anglais sont complets. `assets/i18n/mos.json` (mooré) et `dyu.json` (dioula) sont vides volontairement : les traductions doivent être saisies ou validées par des locuteurs. Les clés vides s'affichent en français. La dictée vocale de la précision utilise la reconnaissance du téléphone en français.

## Comptes de démonstration

Créés par `npm run seed` côté API : `+22670000001` (admin), `+22670000002` (vérificateur), `+22670000003` (agent), mot de passe `demo-2026`.

## Limite à connaître

Ce code n'a pas pu être compilé ni exécuté dans l'environnement où il a été écrit (pas de SDK Flutter). Lancez `flutter analyze` après `tool/setup.sh` et signalez-moi la sortie si une erreur apparaît : les corrections seront rapides.
