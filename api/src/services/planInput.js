import { query } from '../db.js';

export async function loadPlanInput() {
  const [hh, dumps, settings] = await Promise.all([
    query(
      `SELECT ST_Y(g) AS lat, ST_X(g) AS lon, sum(weight)::float AS weight, bool_or(narrow) AS narrow
       FROM (SELECT ST_SnapToGrid(geom::geometry, 0.0005) AS g, weight, narrow FROM buildings) t GROUP BY g`,
    ),
    query(
      `SELECT id, ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon, est_kg, size, waste_type, confidence,
              GREATEST(0, EXTRACT(EPOCH FROM (now() - first_reported_at)) / 86400.0) AS age_days
       FROM dumps WHERE status IN ('verified','scheduled')`,
    ),
    query("SELECT key, value FROM settings WHERE key IN ('depot','landfill')"),
  ]);
  const s = Object.fromEntries(settings.rows.map((r) => [r.key, r.value]));
  const warnings = [];
  if (s.depot.placeholder) warnings.push('depot_a_renseigner');
  if (s.landfill.placeholder) warnings.push('decharge_a_renseigner');
  if (!hh.rowCount) warnings.push('aucun_batiment_importe');
  return {
    body: {
      households: hh.rows.map((r) => ({ lat: r.lat, lon: r.lon, weight: r.weight, narrow: r.narrow })),
      dumps: dumps.rows.map((d) => ({
        id: d.id, lat: d.lat, lon: d.lon, est_kg: d.est_kg, size: d.size, waste_type: d.waste_type,
        confidence: d.confidence, age_days: d.age_days,
      })),
      depot: { lat: s.depot.lat, lon: s.depot.lon },
      landfill: { lat: s.landfill.lat, lon: s.landfill.lon },
    },
    warnings,
  };
}
