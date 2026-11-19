import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { AppError, wrap } from '../middleware/errors.js';
import { requireAuth, requireRole } from '../middleware/auth.js';

const staff = requireRole('verifier', 'admin');
const onlyAdmin = requireRole('admin');

export const adminRoutes = Router();
adminRoutes.use(requireAuth, staff);

adminRoutes.get('/latest', wrap(async (_req, res) => {
  const { rows } = await query(
    "SELECT id, kind, request, result, created_at FROM simulation_runs WHERE kind IN ('plan','simulate') ORDER BY created_at DESC LIMIT 1",
  );
  if (!rows[0]) throw new AppError(404, 'aucun_plan', 'Aucun plan calculé pour le moment');
  const r = rows[0];
  res.json({ run_id: r.id, kind: r.kind, created_at: r.created_at, request: r.request, ...r.result });
}));

adminRoutes.get('/runs', wrap(async (_req, res) => {
  const { rows } = await query(
    "SELECT id, kind, request, created_at FROM simulation_runs WHERE kind IN ('plan','simulate') ORDER BY created_at DESC LIMIT 15",
  );
  res.json({ items: rows });
}));

adminRoutes.get('/runs/:id', wrap(async (req, res) => {
  const id = z.string().uuid().parse(req.params.id);
  const { rows } = await query('SELECT id, kind, request, result, created_at FROM simulation_runs WHERE id = $1', [id]);
  if (!rows[0]) throw new AppError(404, 'introuvable', 'Calcul introuvable');
  const r = rows[0];
  res.json({ run_id: r.id, kind: r.kind, created_at: r.created_at, request: r.request, ...r.result });
}));

adminRoutes.get('/audit', wrap(async (req, res) => {
  const limit = z.coerce.number().int().min(1).max(200).default(30).parse(req.query.limit);
  const [stats, items] = await Promise.all([
    query(`SELECT count(*)::int AS total,
                  count(*) FILTER (WHERE status = 'rejected')::int AS rejected,
                  count(*) FILTER (WHERE status = 'flagged')::int AS flagged,
                  count(*) FILTER (WHERE created_at > now() - interval '24 hours')::int AS last_24h,
                  count(*) FILTER (WHERE status = 'rejected' AND created_at > now() - interval '24 hours')::int AS rejected_24h
           FROM reports`),
    query(
      `SELECT r.id, r.created_at, r.status, r.flags, r.reject_reasons, r.credibility, r.size, r.waste_type,
              ST_Y(r.geom::geometry) AS lat, ST_X(r.geom::geometry) AS lon, u.name AS author
       FROM reports r JOIN users u ON u.id = r.user_id
       WHERE r.status <> 'accepted' OR cardinality(r.flags) > 0
       ORDER BY r.created_at DESC LIMIT $1`,
      [limit],
    ),
  ]);
  res.json({ stats: stats.rows[0], items: items.rows });
}));

const point = z.object({
  name: z.string().max(80).optional(),
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
});

const commune = z.object({
  slug: z.string().regex(/^[a-z0-9-]{2,40}$/),
  name: z.string().min(2).max(100),
  region: z.string().max(80).default(''),
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
  radius_km: z.number().min(1).max(100).default(15),
  population: z.number().int().min(0).nullable().default(null),
  trucks: z.number().int().min(0).max(500).nullable().default(null),
  fuel_price_fcfa: z.number().min(0).max(5000).nullable().default(null),
  depot: point.nullable().default(null),
  landfill: point.nullable().default(null),
});

async function readSetting(key, fallback) {
  const { rows } = await query('SELECT value FROM settings WHERE key = $1', [key]);
  return rows[0] ? rows[0].value : fallback;
}

async function writeSetting(key, value) {
  await query(
    'INSERT INTO settings (key, value) VALUES ($1, $2) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value',
    [key, JSON.stringify(value)],
  );
}

adminRoutes.get('/communes', wrap(async (_req, res) => {
  const [communes, active, depot, landfill] = await Promise.all([
    readSetting('communes', []),
    readSetting('active_commune', null),
    readSetting('depot', null),
    readSetting('landfill', null),
  ]);
  res.json({ communes, active, depot, landfill });
}));

adminRoutes.put('/communes', onlyAdmin, wrap(async (req, res) => {
  const b = z.object({ communes: z.array(commune).min(1).max(50) }).parse(req.body);
  const slugs = new Set(b.communes.map((c) => c.slug));
  if (slugs.size !== b.communes.length) throw new AppError(422, 'doublon', 'Deux communes ont le même identifiant');
  await writeSetting('communes', b.communes);
  const active = await readSetting('active_commune', null);
  if (!slugs.has(active)) await writeSetting('active_commune', b.communes[0].slug);
  res.json({ ok: true });
}));

adminRoutes.post('/communes/:slug/activate', onlyAdmin, wrap(async (req, res) => {
  const list = await readSetting('communes', []);
  const c = list.find((x) => x.slug === req.params.slug);
  if (!c) throw new AppError(404, 'introuvable', 'Commune inconnue');
  await writeSetting('active_commune', c.slug);
  const d = c.depot || { lat: c.lat, lon: c.lon };
  await writeSetting('depot', { lat: d.lat, lon: d.lon, placeholder: false });
  if (c.landfill) await writeSetting('landfill', { lat: c.landfill.lat, lon: c.landfill.lon, placeholder: false });
  res.json({ ok: true, active: c.slug });
}));
