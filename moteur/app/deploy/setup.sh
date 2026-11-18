#!/usr/bin/env sh
# Prépare un serveur OSRM pour le Burkina Faso (distances routières réelles).
set -e
cd "$(dirname "$0")"
mkdir -p data
[ -f data/burkina-faso-latest.osm.pbf ] || curl -L -o data/burkina-faso-latest.osm.pbf https://download.geofabrik.de/africa/burkina-faso-latest.osm.pbf
docker run --rm -v "$PWD/data:/data" ghcr.io/project-osrm/osrm-backend osrm-extract -p /opt/car.lua /data/burkina-faso-latest.osm.pbf
docker run --rm -v "$PWD/data:/data" ghcr.io/project-osrm/osrm-backend osrm-partition /data/burkina-faso-latest.osrm
docker run --rm -v "$PWD/data:/data" ghcr.io/project-osrm/osrm-backend osrm-customize /data/burkina-faso-latest.osrm
docker compose -f docker-compose.osrm.yml up -d
echo "OSRM prêt sur http://localhost:5000. Lancez le moteur avec OSRM_URL=http://localhost:5000"
