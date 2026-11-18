# Verser la carte des dépotoirs dans OpenStreetMap

1. Exporter : `GET /api/public/dumps.osm` (admin). Le fichier contient un point par dépotoir vérifié, avec `amenity=waste_dump_site`, la source et une note.
2. Avant tout import : lire le code de conduite des imports d'OpenStreetMap (wiki « Import/Guidelines ») et **prévenir la communauté** (liste de diffusion ou forum du Burkina Faso). Les imports massifs sans discussion sont annulés.
3. Contrôler le balisage : confirmer que `amenity=waste_dump_site` convient à l'usage local, sinon adapter la balise dans `src/routes/public.js`.
4. Ouvrir le fichier dans JOSM, vérifier chaque point sur l'imagerie, puis envoyer avec un commentaire de modification qui cite la source.
5. Autre voie : `GET /api/public/maproulette.ndjson` pour créer des tâches MapRoulette et laisser la communauté vérifier.

Les données publiées restent sous licence ODbL (voir `DONNEES.md`).
