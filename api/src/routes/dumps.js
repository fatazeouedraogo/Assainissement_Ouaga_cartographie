import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { query, tx } from '../db.js';
import { AppError, wrap } from '../middleware/errors.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { award, awardVerified, savePhoto } from '../services/reports.js';
import { recomputePriority } from '../services/priority.js';
import { notifyAuthors } from '../services/notify.js';

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 8 * 1024 * 1024, files: 1 } });
const staff = requireRole('verifier', 'admin');
const r = Router();
r.use(requireAuth);

const feature = (d) => ({
  type: 'Feature',
  geometry: { type: 'Point', coordinates: [d.lon, d.lat] },
  properties: {
    id: d.id, status: d.status, size: d.size, waste_type: d.waste_type, est_kg: d.est_kg, confidence: d.confidence,
    reporter_count: d.reporter_count, report_count: d.report_count, priority_score: d.priority_score,
    priority_level: d.priority_detail?.level ?? null, main_driver: d.priority_detail?.main_driver ?? null,
    first_reported_at: d.first_reported_at, cleaned_at: d.cleaned_at, scheduled_for: d.scheduled_for,
    before_photo: d.before_photo, after_photo: d.after_photo, recurrence: Boolean(d.recurrence_of),
  },
});

const SELECT = `SELECT d.*, ST_Y(d.geom::geometry) AS lat, ST_X(d.geom::geometry) AS lon FROM dumps d`;

r.get('/', wrap(async (req, res) => {
  const q = z.object({
    bbox: z.string().regex(/^-?\d+(\.\d+)?(,-?\d+(\.\d+)?){3}$/).optional(),
    status: z.string().optional(),
    limit: z.coerce.number().int().min(1).max(5000).default(2000),
  }).parse(req.query);
  const where = [];
  const params = [];
  const isStaff = ['verifier', 'admin'].includes(req.user.role);
  if (!isStaff) {
    params.push(req.user.id);
    where.push(`(d.status IN ('verified','scheduled','cleaned') OR d.id IN (SELECT dump_id FROM reports WHERE user_id = $${params.length}))`);
  }
  if (q.status) {
    const list = q.status.split(',').filter((s) => ['pending', 'verified', 'rejected', 'scheduled', 'cleaned'].includes(s));
    if (list.length) {
      params.push(list);
      where.push(`d.status = ANY($${params.length}::dump_status[])`);
    }
  }
  if (q.bbox) {
    const [w, s, e, n] = q.bbox.split(',').map(Number);
    params.push(w, s, e, n);
    const k = params.length;
    where.push(`d.geom && ST_MakeEnvelope($${k - 3}, $${k - 2}, $${k - 1}, $${k}, 4326)::geography`);
  }
  params.push(q.limit);
  const { rows } = await query(
    `${SELECT} ${where.length ? 'WHERE ' + where.join(' AND ') : ''} ORDER BY d.priority_score DESC, d.last_reported_at DESC LIMIT $${params.length}`,
    params,
  );
  res.json({ type: 'FeatureCollection', features: rows.map(feature) });
}));

r.get('/priorities', wrap(async (_req, res) => {
  const { rows } = await query(
    `${SELECT} WHERE d.status IN ('verified','scheduled') ORDER BY d.priority_score DESC LIMIT 100`,
  );
  res.json({
    items: rows.map((d) => ({ ...feature(d).properties, lat: d.lat, lon: d.lon, detail: d.priority_detail })),
  });
}));

r.post('/recompute-priority', staff, wrap(async (req, res) => {
  const n = await recomputePriority(Boolean(req.body?.rain));
  res.json({ updated: n });
}));

r.get('/:id', wrap(async (req, res) => {
  const id = z.string().uuid().parse(req.params.id);
  const { rows } = await query(`${SELECT} WHERE d.id = $1`, [id]);
  if (!rows[0]) throw new AppError(404, 'dépotoir_introuvable', 'Dépotoir introuvable');
  const reports = await query(
    `SELECT r.id, r.status, r.size, r.waste_type, r.credibility, r.flags, r.created_at, r.photo_path, u.name AS author
     FROM reports r JOIN users u ON u.id = r.user_id WHERE r.dump_id = $1 ORDER BY r.created_at DESC LIMIT 50`,
    [id],
  );
  res.json({ dump: feature(rows[0]), detail: rows[0].priority_detail, reports: reports.rows });
}));

r.post('/:id/verify', staff, wrap(async (req, res) => {
  const id = z.string().uuid().parse(req.params.id);
  await tx(async (c) => {
    const u = await c.query(
      "UPDATE dumps SET status = 'verified', verified_by = $2, verified_at = now() WHERE id = $1 AND status = 'pending' RETURNING id",
      [id, req.user.id],
    );
    if (!u.rowCount) throw new AppError(409, 'statut_invalide', 'Seuls les dépotoirs en attente peuvent être vérifiés');
    await awardVerified(c, id);
    await notifyAuthors(c, id, 'verified', 'Dépotoir confirmé', 'Votre signalement a été confirmé. Il entre dans le plan de la ville.');
  });
  await recomputePriority().catch(() => 0);
  res.json({ ok: true });
}));

r.post('/:id/reject', staff, wrap(async (req, res) => {
  const id = z.string().uuid().parse(req.params.id);
  const reason = z.object({ reason: z.string().trim().min(3).max(200) }).parse(req.body).reason;
  const u = await query(
    "UPDATE dumps SET status = 'rejected', reject_reason = $2 WHERE id = $1 AND status = 'pending' RETURNING id",
    [id, reason],
  );
  if (!u.rowCount) throw new AppError(409, 'statut_invalide', 'Seuls les dépotoirs en attente peuvent être rejetés');
  res.json({ ok: true });
}));

r.post('/:id/schedule', staff, wrap(async (req, res) => {
  const id = z.string().uuid().parse(req.params.id);
  const { date } = z.object({ date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/) }).parse(req.body);
  const u = await query(
    "UPDATE dumps SET status = 'scheduled', scheduled_for = $2 WHERE id = $1 AND status IN ('verified','scheduled') RETURNING id",
    [id, date],
  );
  if (!u.rowCount) throw new AppError(409, 'statut_invalide', 'Le dépotoir doit être vérifié avant d’être programmé');
  await tx((c) => notifyAuthors(c, id, 'scheduled', 'Passage programmé', `Un passage est prévu le ${date}.`));
  res.json({ ok: true });
}));

r.post('/:id/clean', staff, upload.single('photo'), wrap(async (req, res) => {
  const id = z.string().uuid().parse(req.params.id);
  if (!req.file) throw new AppError(422, 'photo_absente', 'La photo après nettoyage est obligatoire');
  const name = savePhoto(req.file.buffer);
  await tx(async (c) => {
    const u = await c.query(
      `UPDATE dumps SET status = 'cleaned', cleaned_at = now(), cleaned_by = $2, after_photo = $3
       WHERE id = $1 AND status IN ('verified','scheduled') RETURNING id`,
      [id, req.user.id, name],
    );
    if (!u.rowCount) throw new AppError(409, 'statut_invalide', 'Ce dépotoir ne peut pas être clôturé');
    const rep = await c.query("SELECT DISTINCT user_id FROM reports WHERE dump_id = $1 AND status <> 'rejected'", [id]);
    for (const row of rep.rows) await award(c, row.user_id, id, 'dump_cleaned', 5);
    await notifyAuthors(c, id, 'cleaned', 'Dépotoir nettoyé', 'Merci : le dépotoir que vous avez signalé a été nettoyé.');
  });
  res.json({ ok: true, after_photo: name });
}));

export default r;
