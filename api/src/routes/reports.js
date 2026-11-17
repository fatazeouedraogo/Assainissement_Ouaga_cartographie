import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { query } from '../db.js';
import { AppError, wrap } from '../middleware/errors.js';
import { requireAuth } from '../middleware/auth.js';
import { submitReport } from '../services/reports.js';

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 8 * 1024 * 1024, files: 1 } });

const fieldsSchema = z.object({
  client_id: z.string().uuid(),
  lat: z.coerce.number().min(-90).max(90),
  lon: z.coerce.number().min(-180).max(180),
  accuracy_m: z.coerce.number().min(0).max(100000).optional(),
  size: z.enum(['small', 'medium', 'large']),
  waste_type: z.enum(['household', 'rubble', 'plastic', 'organic', 'mixed']).default('mixed'),
  note: z.string().trim().max(500).optional(),
  captured_at: z.string().datetime().optional(),
});

const r = Router();
r.use(requireAuth);

r.post('/', upload.single('photo'), wrap(async (req, res) => {
  const f = fieldsSchema.parse(req.body);
  const captured = f.captured_at ? new Date(f.captured_at) : new Date();
  if (captured.getTime() > Date.now() + 5 * 60 * 1000) throw new AppError(422, 'date_future', 'La date de prise de vue est dans le futur');
  const out = await submitReport({
    user: req.user,
    fields: { ...f, captured_at: captured.toISOString() },
    photoBuffer: req.file?.buffer,
    photoMime: req.file?.mimetype,
  });
  const rep = out.report;
  res.status(out.duplicate ? 200 : 201).json({
    duplicate: out.duplicate,
    report: { id: rep.id, status: rep.status, flags: rep.flags, reject_reasons: rep.reject_reasons, credibility: rep.credibility, dump_id: rep.dump_id },
    dump: out.dump ? { id: out.dump.id, status: out.dump.status, confidence: out.dump.confidence, reporter_count: out.dump.reporter_count } : null,
    points_awarded: out.points || 0,
  });
}));

r.get('/mine', wrap(async (req, res) => {
  const { rows } = await query(
    `SELECT r.id, r.status, r.flags, r.reject_reasons, r.size, r.waste_type, r.created_at, r.photo_path, r.dump_id,
            ST_Y(r.geom::geometry) AS lat, ST_X(r.geom::geometry) AS lon, d.status AS dump_status
     FROM reports r LEFT JOIN dumps d ON d.id = r.dump_id
     WHERE r.user_id = $1 ORDER BY r.created_at DESC LIMIT 100`,
    [req.user.id],
  );
  res.json({ reports: rows });
}));

export default r;
