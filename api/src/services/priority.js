import { query } from '../db.js';
import { engine } from './engine.js';

export async function recomputePriority(rain = false) {
  const dumps = await query(
    `SELECT id, ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon, est_kg, size, waste_type, confidence,
            GREATEST(0, EXTRACT(EPOCH FROM (now() - first_reported_at)) / 86400.0) AS age_days
     FROM dumps WHERE status IN ('pending','verified','scheduled')`,
  );
  if (!dumps.rowCount) return 0;
  const pois = await query(
    `SELECT DISTINCT p.id, p.kind, p.name, ST_Y(p.geom::geometry) AS lat, ST_X(p.geom::geometry) AS lon
     FROM poi p JOIN dumps d ON ST_DWithin(p.geom, d.geom, 600) WHERE d.status IN ('pending','verified','scheduled')`,
  );
  const res = await engine.priority({
    dumps: dumps.rows.map((d) => ({
      id: d.id, lat: d.lat, lon: d.lon, est_kg: d.est_kg, size: d.size, waste_type: d.waste_type,
      confidence: d.confidence, age_days: d.age_days,
    })),
    pois: pois.rows.map((p) => ({ kind: p.kind, name: p.name, lat: p.lat, lon: p.lon })),
    rain,
  });
  const ids = res.scores.map((s) => s.id);
  await query(
    `UPDATE dumps d SET priority_score = v.score, priority_detail = v.detail
     FROM (SELECT unnest($1::uuid[]) AS id, unnest($2::real[]) AS score, unnest($3::jsonb[]) AS detail) v
     WHERE d.id = v.id`,
    [ids, res.scores.map((s) => s.score), res.scores.map((s) => JSON.stringify(s))],
  );
  return ids.length;
}
