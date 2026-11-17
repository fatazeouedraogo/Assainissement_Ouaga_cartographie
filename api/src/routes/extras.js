import crypto from 'node:crypto';
import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { query, tx } from '../db.js';
import { AppError, wrap } from '../middleware/errors.js';
import { optionalAuth, requireAuth, requireRole } from '../middleware/auth.js';
import { engine } from '../services/engine.js';
import { loadPlanInput } from '../services/planInput.js';
import { recomputePriority } from '../services/priority.js';
import { getOverview } from '../services/overview.js';
import { buildReport } from '../services/report.js';
import { forecast } from '../services/weather.js';
import { graph, handleMessage, parseMessages, verifySignature } from '../services/whatsapp.js';
import { whatsapp } from '../config.js';

const staff = requireRole('verifier', 'admin');
const admin = requireRole('admin');
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 25 * 1024 * 1024, files: 1 } });

const pct = (v) => `${(v * 100).toFixed(1).replace('.', ',')} %`;
const money = (v) => `${Math.round(v).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ')} FCFA`;

async function needInput() {
  const { body, warnings } = await loadPlanInput();
  if (!body.households.length) throw new AppError(409, 'aucun_batiment', 'Importez les bâtiments avant de lancer un calcul');
  return { body, warnings };
}

export const insights = Router();
insights.use(requireAuth);

insights.post('/ask', staff, wrap(async (req, res) => {
  const { question } = z.object({ question: z.string().trim().min(3).max(500) }).parse(req.body);
  const parsed = await engine.assistant({ question });
  if (!parsed.recognized) {
    throw new AppError(422, 'question_non_comprise', 'Je n’ai pas reconnu de changement à simuler. Exemple : « et si on avait 3 camions de plus pendant la saison des pluies ? »');
  }
  if (parsed.needs.length && !parsed.events.length && !Object.keys(parsed.params).length) {
    return res.json({ answer: `Précisez : ${parsed.needs.join(', ')}.`, needs: parsed.needs, parsed });
  }
  const { body, warnings } = await needInput();
  const out = await engine.compare({
    ...body,
    base_params: {},
    scenarios: [
      { name: 'Situation actuelle', params: {}, events: [] },
      { name: 'Votre question', params: parsed.params, events: parsed.events },
    ],
    time_limit_s: 3,
  });
  const [a, b] = out.scenarios.map((s) => s.headline);
  const dpts = (b.collection_rate.mean - a.collection_rate.mean) * 100;
  const sign = (n) => `${n >= 0 ? '+' : '−'}${Math.abs(n).toFixed(1).replace('.', ',')} pts`;
  const dcost = b.cost_per_month - a.cost_per_month;
  let answer = `Avec ${parsed.understood.join(', ')} : la collecte passe de ${pct(a.collection_rate.mean)} à ${pct(b.collection_rate.mean)} (${sign(dpts)}), `
    + `les fuites vers les dépotoirs de ${pct(a.leakage_rate.mean)} à ${pct(b.leakage_rate.mean)}. `
    + `Le coût mensuel passe de ${money(a.cost_per_month)} à ${money(b.cost_per_month)} (${dcost >= 0 ? '+' : '−'}${money(Math.abs(dcost))}).`;
  if (!b.within_budget) answer += ' Attention : ce scénario dépasse le budget.';
  if (parsed.needs.length) answer += ` Non pris en compte : ${parsed.needs.join(', ')}.`;
  res.json({ answer, parsed, comparison: out.scenarios, warnings });
}));

insights.post('/recommend', staff, wrap(async (req, res) => {
  const b = z.object({ params: z.record(z.any()).default({}), events: z.array(z.record(z.any())).default([]) }).parse(req.body);
  const { body, warnings } = await needInput();
  res.json({ warnings, ...(await engine.recommend({ ...body, params: b.params, events: b.events, time_limit_s: 2 })) });
}));

insights.post('/pareto', staff, wrap(async (req, res) => {
  const b = z.object({ params: z.record(z.any()).default({}), events: z.array(z.record(z.any())).default([]) }).parse(req.body);
  const { body } = await needInput();
  res.json(await engine.pareto({ ...body, params: b.params, events: b.events, candidates: 8, time_limit_s: 1 }));
}));

insights.post('/calibrate', admin, wrap(async (req, res) => {
  const b = z.object({
    metric: z.enum(['collection_rate', 'leakage_rate']).default('collection_rate'),
    target: z.number().min(0).max(1),
    parameter: z.string().default('subscription_rate'),
    low: z.number(),
    high: z.number(),
    params: z.record(z.any()).default({}),
  }).parse(req.body);
  const { body } = await needInput();
  res.json(await engine.calibrate({ ...body, ...b, time_limit_s: 2 }));
}));

insights.get('/risk', wrap(async (_req, res) => {
  const [hh, hist, pois, open] = await Promise.all([
    query(`SELECT ST_Y(g) AS lat, ST_X(g) AS lon, sum(weight)::float AS weight FROM (SELECT ST_SnapToGrid(geom::geometry, 0.0005) AS g, weight FROM buildings) t GROUP BY g`),
    query(`SELECT ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon, recurrence_of IS NOT NULL AS recurrence FROM dumps WHERE status <> 'rejected'`),
    query(`SELECT kind, name, ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon FROM poi LIMIT 5000`),
    query(`SELECT id, ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon FROM dumps WHERE status IN ('pending','verified','scheduled')`),
  ]);
  if (!hh.rowCount) throw new AppError(409, 'aucun_batiment', 'Aucun bâtiment importé');
  res.json(await engine.risk({ households: hh.rows, history: hist.rows, pois: pois.rows, open_dumps: open.rows, top: 25 }));
}));

insights.get('/weather', wrap(async (_req, res) => res.json(await forecast())));

insights.post('/report.pdf', staff, wrap(async (req, res) => {
  const { rows } = await query("SELECT result FROM simulation_runs WHERE kind IN ('plan','simulate') ORDER BY created_at DESC LIMIT 1");
  if (!rows[0]) throw new AppError(404, 'aucun_plan', 'Calculez d’abord un plan');
  const r = rows[0].result;
  const { warnings } = await loadPlanInput();
  const doc = buildReport({ plan: r.plan, simulation: r.simulation, warnings, overview: await getOverview() });
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', 'attachment; filename="note-de-decision.pdf"');
  doc.pipe(res);
}));

export const notifications = Router();
notifications.use(requireAuth);
notifications.get('/', wrap(async (req, res) => {
  const { rows } = await query('SELECT id, kind, dump_id, title, body, read_at, created_at FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50', [req.user.id]);
  res.json({ unread: rows.filter((n) => !n.read_at).length, items: rows });
}));
notifications.post('/read', wrap(async (req, res) => {
  await query('UPDATE notifications SET read_at = now() WHERE user_id = $1 AND read_at IS NULL', [req.user.id]);
  res.json({ ok: true });
}));

export const iot = Router();
const hash = (s) => crypto.createHash('sha256').update(s).digest('hex');
iot.post('/sensors', requireAuth, admin, wrap(async (req, res) => {
  const b = z.object({ id: z.string().regex(/^[a-z0-9-]{3,40}$/), name: z.string().min(2).max(80), lat: z.number(), lon: z.number(), height_cm: z.number().min(40).max(400).default(120), min_cm: z.number().min(2).max(60).default(10) }).parse(req.body);
  const secret = crypto.randomBytes(18).toString('hex');
  await query(
    `INSERT INTO sensors (id, name, geom, height_cm, min_cm, secret_hash) VALUES ($1, $2, ST_SetSRID(ST_MakePoint($4, $3), 4326)::geography, $5, $6, $7)`,
    [b.id, b.name, b.lat, b.lon, b.height_cm, b.min_cm, hash(secret)],
  );
  res.status(201).json({ id: b.id, secret, note: 'Notez ce secret : il ne sera plus affiché.' });
}));
iot.post('/readings', wrap(async (req, res) => {
  const b = z.object({ sensor_id: z.string(), distance_cm: z.number().min(0).max(1000), battery: z.number().min(0).max(100).optional() }).parse(req.body);
  const { rows } = await query('SELECT height_cm, min_cm, secret_hash FROM sensors WHERE id = $1', [b.sensor_id]);
  const key = String(req.headers['x-device-key'] || '');
  const ok = rows[0] && crypto.timingSafeEqual(Buffer.from(hash(key)), Buffer.from(rows[0].secret_hash));
  if (!ok) throw new AppError(401, 'capteur_inconnu', 'Capteur ou clé invalide');
  const { height_cm: h, min_cm: m } = rows[0];
  const fill = Math.min(1, Math.max(0, (h - b.distance_cm) / (h - m)));
  await query('INSERT INTO sensor_readings (sensor_id, distance_cm, fill_ratio, battery) VALUES ($1, $2, $3, $4)', [b.sensor_id, b.distance_cm, fill, b.battery ?? null]);
  res.status(201).json({ fill_ratio: Number(fill.toFixed(3)) });
}));
iot.get('/status', requireAuth, staff, wrap(async (_req, res) => {
  const { rows } = await query(
    `SELECT DISTINCT ON (s.id) s.id, s.name, ST_Y(s.geom::geometry) AS lat, ST_X(s.geom::geometry) AS lon, r.fill_ratio, r.battery, r.at
     FROM sensors s LEFT JOIN sensor_readings r ON r.sensor_id = s.id ORDER BY s.id, r.at DESC`,
  );
  res.json({ sensors: rows.map((s) => ({ ...s, urgent: (s.fill_ratio ?? 0) >= 0.8, stale: !s.at || Date.now() - new Date(s.at).getTime() > 6 * 3600 * 1000 })) });
}));

export const candidates = Router();
candidates.use(requireAuth, staff);

const REASONS = ['batiment', 'route', 'eau', 'vegetation', 'rien_vu', 'deja_signale', 'autre'];
const DETECT_DEFAULT = { min_score: 1.5, merge_m: 40, risk_weight: 0.5 };
const SIZE_KG = { small: 50, medium: 300, large: 1500 };

async function detectionSettings() {
  const { rows } = await query("SELECT value FROM settings WHERE key = 'detection'");
  return { ...DETECT_DEFAULT, ...(rows[0]?.value || {}) };
}

async function riskCells() {
  try {
    const hh = await query('SELECT ST_Y(g) AS lat, ST_X(g) AS lon, sum(weight)::float AS weight FROM (SELECT ST_SnapToGrid(geom::geometry, 0.0005) AS g, weight FROM buildings) t GROUP BY g');
    if (!hh.rowCount) return [];
    const [hist, pois] = await Promise.all([
      query("SELECT ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon, recurrence_of IS NOT NULL AS recurrence FROM dumps WHERE status <> 'rejected'"),
      query('SELECT kind, ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon FROM poi LIMIT 5000'),
    ]);
    return (await engine.risk({ households: hh.rows, history: hist.rows, pois: pois.rows, open_dumps: [], top: 100 })).cells;
  } catch {
    return [];
  }
}

candidates.post('/scan', admin, upload.single('image'), wrap(async (req, res) => {
  if (!req.file) throw new AppError(422, 'image_absente', 'Image aérienne requise');
  const b = z.object({
    south: z.coerce.number(), west: z.coerce.number(), north: z.coerce.number(), east: z.coerce.number(),
    masks: z.string().optional(),
  }).parse(req.body);
  let masks;
  if (b.masks) {
    try {
      masks = JSON.parse(b.masks);
    } catch {
      throw new AppError(422, 'masques_invalides', 'Le fichier de masques OpenStreetMap est illisible');
    }
  }
  const cfg = await detectionSettings();
  const out = await engine.candidates(req.file.buffer, req.file.mimetype, { south: b.south, west: b.west, north: b.north, east: b.east }, {
    ...cfg, masks, riskCells: await riskCells(), top: 60,
  });
  let added = 0;
  for (const c of out.candidates) {
    const r = await query(
      `INSERT INTO candidates (geom, score, base_score, signals, merged)
       SELECT ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $3, $4, $5, $6
       WHERE NOT EXISTS (SELECT 1 FROM candidates WHERE status = 'new' AND ST_DWithin(geom, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $7))
         AND NOT EXISTS (SELECT 1 FROM dumps WHERE status <> 'rejected' AND ST_DWithin(geom, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $7))`,
      [c.lat, c.lon, c.score, c.base_score, JSON.stringify(c.signals), c.merged || 0, cfg.merge_m],
    );
    added += r.rowCount;
  }
  res.status(201).json({ found: out.candidates.length, added, excluded: out.stats.excluded, settings: cfg });
}));

candidates.get('/', wrap(async (_req, res) => {
  const { rows } = await query(
    "SELECT id, score, base_score, signals, merged, status, ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lon FROM candidates WHERE status = 'new' ORDER BY score DESC LIMIT 300",
  );
  res.json({ candidates: rows });
}));

candidates.get('/stats', wrap(async (_req, res) => {
  const { rows } = await query("SELECT score, status, reject_reason FROM candidates WHERE status IN ('confirmed','dismissed')");
  const counts = await query('SELECT status, count(*)::int AS n FROM candidates GROUP BY status');
  const by = Object.fromEntries(counts.rows.map((r) => [r.status, r.n]));
  const confirmed = rows.filter((r) => r.status === 'confirmed');
  const reviewed = rows.length;
  const reasons = {};
  for (const r of rows) if (r.reject_reason) reasons[r.reject_reason] = (reasons[r.reject_reason] || 0) + 1;
  const thresholds = [1.5, 2, 3, 4, 6, 8].map((t) => {
    const kept = rows.filter((r) => r.score >= t);
    const ok = kept.filter((r) => r.status === 'confirmed').length;
    return { threshold: t, reviewed: kept.length, confirmed: ok, precision: kept.length ? Number((ok / kept.length).toFixed(3)) : null };
  });
  const suggested = thresholds.find((t) => t.reviewed >= 5 && t.precision >= 0.7)?.threshold ?? null;
  res.json({
    pending: by.new || 0,
    confirmed: by.confirmed || 0,
    dismissed: by.dismissed || 0,
    reviewed,
    precision: reviewed ? Number((confirmed.length / reviewed).toFixed(3)) : null,
    reject_reasons: reasons,
    thresholds,
    suggested_threshold: suggested,
    current: await detectionSettings(),
    note: reviewed < 10 ? 'Moins de 10 candidats vérifiés : la précision est encore peu fiable.' : null,
  });
}));

candidates.post('/:id/confirm', wrap(async (req, res) => {
  const id = z.string().uuid().parse(req.params.id);
  const b = z.object({ size: z.enum(['small', 'medium', 'large']).default('medium'), waste_type: z.enum(['household', 'rubble', 'plastic', 'organic', 'mixed']).default('mixed') }).parse(req.body || {});
  const dumpId = await tx(async (c) => {
    const cand = await c.query("SELECT id, geom FROM candidates WHERE id = $1 AND status = 'new' FOR UPDATE", [id]);
    if (!cand.rows[0]) throw new AppError(409, 'statut_invalide', 'Ce candidat a déjà été traité');
    const d = await c.query(
      `INSERT INTO dumps (geom, size, waste_type, est_kg, status, confidence, verified_by, verified_at)
       VALUES ($1, $2, $3, $4, 'verified', 1, $5, now()) RETURNING id`,
      [cand.rows[0].geom, b.size, b.waste_type, SIZE_KG[b.size], req.user.id],
    );
    await c.query("UPDATE candidates SET status = 'confirmed', reviewed_by = $2, reviewed_at = now(), dump_id = $3 WHERE id = $1", [id, req.user.id, d.rows[0].id]);
    return d.rows[0].id;
  });
  recomputePriority().catch(() => 0);
  res.status(201).json({ ok: true, dump_id: dumpId });
}));

candidates.post('/:id/dismiss', wrap(async (req, res) => {
  const id = z.string().uuid().parse(req.params.id);
  const b = z.object({ reason: z.enum(REASONS), note: z.string().trim().max(300).optional() }).parse(req.body || {});
  const u = await query(
    "UPDATE candidates SET status = 'dismissed', reviewed_by = $2, reviewed_at = now(), reject_reason = $3, reject_note = $4 WHERE id = $1 AND status = 'new' RETURNING id",
    [id, req.user.id, b.reason, b.note ?? null],
  );
  if (!u.rowCount) throw new AppError(409, 'statut_invalide', 'Ce candidat a déjà été traité');
  res.json({ ok: true });
}));

export const subscriptions = Router();
subscriptions.get('/price', wrap(async (_req, res) => {
  const { rows } = await query("SELECT value FROM settings WHERE key = 'subscription'");
  res.json({ price_month: rows[0].value.price_month, placeholder: Boolean(rows[0].value.placeholder), simulated: true });
}));
subscriptions.post('/pay', requireAuth, wrap(async (req, res) => {
  const b = z.object({ provider: z.enum(['orange', 'moov']), wallet_phone: z.string().regex(/^\+?[0-9]{8,15}$/), months: z.number().int().min(1).max(12) }).parse(req.body);
  const price = (await query("SELECT value FROM settings WHERE key = 'subscription'")).rows[0].value.price_month;
  const last = await query('SELECT max(paid_until) AS d FROM subscriptions WHERE user_id = $1', [req.user.id]);
  const { rows } = await query(
    `INSERT INTO subscriptions (user_id, provider, wallet_phone, months, amount, status, reference, paid_until)
     VALUES ($1, $2, $3, $4::int, $5, 'success', $6, (GREATEST(COALESCE($7::date, CURRENT_DATE), CURRENT_DATE) + make_interval(months => $4::int))::date)
     RETURNING id, provider, months, amount, status, reference, simulated, paid_until`,
    [req.user.id, b.provider, b.wallet_phone, b.months, price * b.months, `SIM-${crypto.randomBytes(5).toString('hex').toUpperCase()}`, last.rows[0].d],
  );
  res.status(201).json({ ...rows[0], notice: 'Paiement simulé : aucun argent réel n’a été débité.' });
}));
subscriptions.get('/mine', requireAuth, wrap(async (req, res) => {
  const { rows } = await query('SELECT id, provider, months, amount, status, reference, simulated, paid_until, created_at FROM subscriptions WHERE user_id = $1 ORDER BY created_at DESC LIMIT 20', [req.user.id]);
  res.json({ payments: rows, active_until: rows[0]?.paid_until ?? null });
}));

export const whatsappRoutes = Router();
whatsappRoutes.get('/webhook', (req, res) => {
  if (req.query['hub.mode'] === 'subscribe' && whatsapp.verifyToken && req.query['hub.verify_token'] === whatsapp.verifyToken) {
    return res.status(200).send(String(req.query['hub.challenge']));
  }
  res.sendStatus(403);
});
whatsappRoutes.post('/webhook', wrap(async (req, res) => {
  if (!verifySignature(req.rawBody || Buffer.alloc(0), req.headers['x-hub-signature-256'])) return res.sendStatus(401);
  res.sendStatus(200);
  for (const msg of parseMessages(req.body)) {
    handleMessage(msg, graph).catch((e) => console.error('whatsapp', e.message));
  }
}));
