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
