import { Router } from 'express';
import { query } from '../db.js';
import { wrap } from '../middleware/errors.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { getOverview } from '../services/overview.js';

const r = Router();

r.get('/overview', wrap(async (_req, res) => res.json(await getOverview())));

r.get('/hotspots', wrap(async (_req, res) => {
  const { rows } = await query(
    `SELECT ST_Y(g) AS lat, ST_X(g) AS lon, count(*)::int AS dumps, count(*) FILTER (WHERE recurrence_of IS NOT NULL)::int AS recurrences
     FROM (SELECT ST_SnapToGrid(geom::geometry, 0.001) AS g, recurrence_of FROM dumps WHERE status <> 'rejected') t
     GROUP BY g HAVING count(*) >= 2 ORDER BY recurrences DESC, dumps DESC LIMIT 20`,
  );
  res.json({ hotspots: rows });
}));

r.get('/leaderboard', wrap(async (_req, res) => {
  const { rows } = await query("SELECT name, points FROM users WHERE points > 0 AND role IN ('citizen','agent') ORDER BY points DESC LIMIT 20");
  res.json({ leaders: rows.map((u, i) => ({ rank: i + 1, name: u.name.split(' ')[0], points: u.points })) });
}));

r.get('/dumps.geojson', wrap(async (_req, res) => {
  const { rows } = await query(
    `SELECT id, ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon, status, size, waste_type, est_kg, first_reported_at, cleaned_at
     FROM dumps WHERE status IN ('verified','scheduled','cleaned')`,
  );
  res.type('application/geo+json').json({
    type: 'FeatureCollection',
    features: rows.map((d) => ({ type: 'Feature', geometry: { type: 'Point', coordinates: [d.lon, d.lat] }, properties: { id: d.id, status: d.status, size: d.size, waste_type: d.waste_type, est_kg: d.est_kg, first_reported_at: d.first_reported_at, cleaned_at: d.cleaned_at } })),
  });
}));

const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const OPEN = "status IN ('verified','scheduled','cleaned')";

r.get('/dumps.csv', wrap(async (_req, res) => {
  const { rows } = await query(`SELECT id, ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon, status, size, waste_type, est_kg, first_reported_at, cleaned_at FROM dumps WHERE ${OPEN} ORDER BY first_reported_at`);
  const head = 'id,lat,lon,status,size,waste_type,est_kg,first_reported_at,cleaned_at';
  const body = rows.map((d) => [d.id, d.lat, d.lon, d.status, d.size, d.waste_type, d.est_kg, d.first_reported_at?.toISOString?.() ?? '', d.cleaned_at?.toISOString?.() ?? ''].join(','));
  res.type('text/csv').send([head, ...body].join('\n'));
}));

r.get('/dumps.osm', requireAuth, requireRole('admin'), wrap(async (_req, res) => {
  const { rows } = await query("SELECT id, ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon, size, waste_type, est_kg FROM dumps WHERE status IN ('verified','scheduled')");
  const nodes = rows.map((d, i) => `  <node id="-${i + 1}" action="modify" visible="true" lat="${d.lat}" lon="${d.lon}">\n    <tag k="amenity" v="waste_dump_site"/>\n    <tag k="source" v="signalements citoyens vérifiés (Ouaga Propre)"/>\n    <tag k="note" v="${esc(`Dépotoir sauvage, taille ${d.size}, environ ${Math.round(d.est_kg)} kg`)}"/>\n    <tag k="fixme" v="vérifier le balisage avant import ; id ${d.id.slice(0, 8)}"/>\n  </node>`);
  res.type('application/xml').send(`<?xml version="1.0" encoding="UTF-8"?>\n<osm version="0.6" generator="ouaga-propre">\n${nodes.join('\n')}\n</osm>\n`);
}));

r.get('/datapackage.json', wrap(async (_req, res) => {
  const n = (await query(`SELECT count(*)::int AS n FROM dumps WHERE ${OPEN}`)).rows[0].n;
  res.json({
    name: 'depotoirs-ouagadougou',
    title: 'Dépotoirs sauvages vérifiés de Ouagadougou',
    description: 'Dépotoirs signalés par les habitants et vérifiés sur le terrain. Coordonnées WGS84.',
    licenses: [{ name: 'ODbL-1.0', path: 'https://opendatacommons.org/licenses/odbl/1-0/', title: 'Open Database License' }],
    attribution: 'Signalements citoyens vérifiés (Ouaga Propre). Fond de carte : © contributeurs OpenStreetMap.',
    generated_at: new Date().toISOString(),
    resources: [
      { name: 'depotoirs', path: '/api/public/dumps.csv', format: 'csv', mediatype: 'text/csv', rows: n },
      { name: 'depotoirs-geojson', path: '/api/public/dumps.geojson', format: 'geojson', mediatype: 'application/geo+json', rows: n },
    ],
    fields: [
      { name: 'status', description: 'verified, scheduled ou cleaned' },
      { name: 'size', description: 'small, medium ou large' },
      { name: 'est_kg', description: 'masse estimée en kg (indicative)' },
    ],
  });
}));

r.get('/maproulette.ndjson', requireAuth, requireRole('admin'), wrap(async (_req, res) => {
  const { rows } = await query(
    `SELECT id, ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon, size, waste_type
     FROM dumps WHERE status IN ('verified','scheduled')`,
  );
  res.type('application/x-ndjson').send(
    rows.map((d) => JSON.stringify({ type: 'Feature', geometry: { type: 'Point', coordinates: [d.lon, d.lat] }, properties: { name: `Dépotoir sauvage ${d.id.slice(0, 8)}`, instruction: `Ajouter un point amenity=waste_disposal ou un tag « dumpsite » après vérification sur image. Taille : ${d.size}, type : ${d.waste_type}.`, source_id: d.id } })).join('\n'),
  );
}));

export default r;
