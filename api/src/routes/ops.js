import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { AppError, wrap } from '../middleware/errors.js';
import { optionalAuth, requireAuth, requireRole } from '../middleware/auth.js';
import { engine } from '../services/engine.js';
import { loadPlanInput } from '../services/planInput.js';

const staff = requireRole('verifier', 'admin');
const admin = requireRole('admin');

const event = z.object({
  kind: z.enum(['truck_breakdown', 'rain_season', 'new_district', 'budget_cut', 'subscription_drop', 'more_trucks']),
  value: z.number().optional(),
  households: z.array(z.object({ lat: z.number(), lon: z.number(), weight: z.number().positive().default(1) })).optional(),
  label: z.string().optional(),
});
const planBody = z.object({
  params: z.record(z.any()).default({}),
  events: z.array(event).default([]),
  simulate: z.boolean().default(true),
  time_limit_s: z.number().int().min(1).max(30).default(6),
});

async function saveRun(kind, request, result, userId, scenarioId = null) {
  const { rows } = await query(
    'INSERT INTO simulation_runs (scenario_id, kind, request, result, created_by) VALUES ($1, $2, $3, $4, $5) RETURNING id, created_at',
    [scenarioId, kind, JSON.stringify(request), JSON.stringify(result), userId],
  );
  return rows[0];
}

export const plan = Router();
plan.use(requireAuth, staff);

plan.get('/controls', wrap(async (_req, res) => res.json(await engine.controls())));

plan.post('/', wrap(async (req, res) => {
  const b = planBody.parse(req.body);
  const { body, warnings } = await loadPlanInput();
  if (!body.households.length) throw new AppError(409, 'aucun_batiment', 'Importez les bâtiments avant de lancer un plan');
  const payload = { ...body, params: b.params, events: b.events, time_limit_s: b.time_limit_s };
  const result = b.simulate ? await engine.simulate(payload) : { plan: await engine.plan(payload) };
  const run = await saveRun(b.simulate ? 'simulate' : 'plan', { params: b.params, events: b.events }, result, req.user.id);
  res.json({ run_id: run.id, created_at: run.created_at, warnings, ...result });
}));

plan.get('/latest', wrap(async (_req, res) => {
  const { rows } = await query(
    "SELECT id, kind, result, created_at FROM simulation_runs WHERE kind IN ('plan','simulate') ORDER BY created_at DESC LIMIT 1",
  );
  if (!rows[0]) throw new AppError(404, 'aucun_plan', 'Aucun plan calculé pour le moment');
  res.json({ run_id: rows[0].id, created_at: rows[0].created_at, ...rows[0].result });
}));

plan.post('/sensitivity', wrap(async (req, res) => {
  const b = planBody.extend({ delta: z.number().min(0.05).max(0.8).default(0.2), parameters: z.array(z.string()).optional() }).parse(req.body);
  const { body } = await loadPlanInput();
  if (!body.households.length) throw new AppError(409, 'aucun_batiment', 'Importez les bâtiments avant de lancer une analyse');
  const result = await engine.sensitivity({ ...body, params: b.params, events: b.events, delta: b.delta, parameters: b.parameters, time_limit_s: 2 });
  const run = await saveRun('sensitivity', { params: b.params }, result, req.user.id);
  res.json({ run_id: run.id, ...result });
}));

export const scenarios = Router();
scenarios.use(requireAuth, staff);

const scenarioBody = z.object({ name: z.string().trim().min(2).max(80), params: z.record(z.any()).default({}), events: z.array(event).default([]) });

scenarios.get('/', wrap(async (_req, res) => {
  const { rows } = await query('SELECT id, name, params, events, created_at FROM scenarios ORDER BY created_at DESC LIMIT 100');
  res.json({ scenarios: rows });
}));

scenarios.post('/', wrap(async (req, res) => {
  const b = scenarioBody.parse(req.body);
  const { rows } = await query(
    'INSERT INTO scenarios (name, params, events, created_by) VALUES ($1, $2, $3, $4) RETURNING id, name, params, events, created_at',
    [b.name, JSON.stringify(b.params), JSON.stringify(b.events), req.user.id],
  );
  res.status(201).json(rows[0]);
}));

scenarios.delete('/:id', wrap(async (req, res) => {
  const id = z.string().uuid().parse(req.params.id);
  await query('DELETE FROM scenarios WHERE id = $1', [id]);
  res.status(204).end();
}));

scenarios.post('/compare', wrap(async (req, res) => {
  const b = z.object({
    ids: z.array(z.string().uuid()).default([]),
    inline: z.array(scenarioBody).default([]),
    base_params: z.record(z.any()).default({}),
  }).parse(req.body);
  let items = [...b.inline];
  if (b.ids.length) {
    const { rows } = await query('SELECT id, name, params, events FROM scenarios WHERE id = ANY($1::uuid[])', [b.ids]);
    const byId = new Map(rows.map((r) => [r.id, r]));
    items = [...b.ids.map((i) => byId.get(i)).filter(Boolean), ...items];
  }
  if (items.length < 1 || items.length > 8) throw new AppError(422, 'scenarios_invalides', 'Choisissez entre 1 et 8 scénarios');
  const { body, warnings } = await loadPlanInput();
  if (!body.households.length) throw new AppError(409, 'aucun_batiment', 'Importez les bâtiments avant de comparer');
  const result = await engine.compare({
    ...body,
    base_params: b.base_params,
    scenarios: items.map((s) => ({ name: s.name, params: s.params, events: s.events })),
    time_limit_s: 3,
  });
  const run = await saveRun('compare', { items }, result, req.user.id);
  res.json({ run_id: run.id, warnings, ...result });
}));

export const poi = Router();
poi.post('/bulk', requireAuth, admin, wrap(async (req, res) => {
  const b = z.object({
    items: z.array(z.object({ kind: z.enum(['school', 'market', 'health', 'drain', 'water']), name: z.string().nullable().optional(), lat: z.number(), lon: z.number() })).min(1).max(1000),
  }).parse(req.body);
  await query(
    `INSERT INTO poi (kind, name, geom)
     SELECT k, n, ST_SetSRID(ST_MakePoint(lo, la), 4326)::geography
     FROM unnest($1::poi_kind[], $2::text[], $3::float8[], $4::float8[]) AS t(k, n, la, lo)`,
    [b.items.map((i) => i.kind), b.items.map((i) => i.name ?? null), b.items.map((i) => i.lat), b.items.map((i) => i.lon)],
  );
  res.status(201).json({ inserted: b.items.length });
}));
poi.get('/', optionalAuth, wrap(async (_req, res) => {
  const { rows } = await query(
    "SELECT id, kind, name, ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon FROM poi LIMIT 5000",
  );
  res.json({ items: rows });
}));

export const buildings = Router();
buildings.post('/bulk', requireAuth, admin, wrap(async (req, res) => {
  const b = z.object({
    source: z.string().default('open_buildings'),
    items: z.array(z.object({ lat: z.number(), lon: z.number(), weight: z.number().positive().default(1), narrow: z.boolean().default(false) })).min(1).max(5000),
  }).parse(req.body);
  await query(
    `INSERT INTO buildings (geom, weight, narrow, source)
     SELECT ST_SetSRID(ST_MakePoint(lo, la), 4326)::geography, w, nr, $5
     FROM unnest($1::float8[], $2::float8[], $3::real[], $4::boolean[]) AS t(la, lo, w, nr)`,
    [b.items.map((i) => i.lat), b.items.map((i) => i.lon), b.items.map((i) => i.weight), b.items.map((i) => i.narrow), b.source],
  );
  res.status(201).json({ inserted: b.items.length });
}));

export const settings = Router();
settings.get('/', requireAuth, staff, wrap(async (_req, res) => {
  const { rows } = await query('SELECT key, value FROM settings');
  res.json(Object.fromEntries(rows.map((r) => [r.key, r.value])));
}));
settings.put('/:key', requireAuth, admin, wrap(async (req, res) => {
  const key = z.enum(['depot', 'landfill', 'thresholds']).parse(req.params.key);
  const schema = key === 'thresholds'
    ? z.object({ auto_verify_confidence: z.number().min(0.5).max(0.99), auto_verify_reporters: z.number().int().min(1).max(20), duplicate_radius_m: z.number().min(5).max(200) })
    : z.object({ lat: z.number().min(12.25).max(12.5), lon: z.number().min(-1.7).max(-1.35) });
  const v = schema.parse(req.body);
  await query('UPDATE settings SET value = $2 WHERE key = $1', [key, JSON.stringify(key === 'thresholds' ? v : { ...v, placeholder: false })]);
  res.json({ ok: true });
}));
