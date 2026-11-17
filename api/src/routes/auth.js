import bcrypt from 'bcryptjs';
import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { AppError, wrap } from '../middleware/errors.js';
import { requireAuth, sign } from '../middleware/auth.js';

const phone = z.string().trim().regex(/^\+?[0-9 ]{8,15}$/, 'Numéro de téléphone invalide').transform((v) => v.replace(/ /g, ''));
const registerSchema = z.object({ name: z.string().trim().min(2).max(60), phone, password: z.string().min(6).max(100) });
const loginSchema = z.object({ phone, password: z.string().min(1) });

export const publicUser = (u) => ({ id: u.id, name: u.name, phone: u.phone, role: u.role, points: u.points });

const r = Router();

r.post('/register', wrap(async (req, res) => {
  const b = registerSchema.parse(req.body);
  const hash = await bcrypt.hash(b.password, 10);
  try {
    const { rows } = await query(
      'INSERT INTO users (name, phone, password_hash) VALUES ($1, $2, $3) RETURNING id, name, phone, role, points',
      [b.name, b.phone, hash],
    );
    res.status(201).json({ token: sign(rows[0]), user: publicUser(rows[0]) });
  } catch (e) {
    if (e.code === '23505') throw new AppError(409, 'telephone_deja_utilise', 'Ce numéro est déjà inscrit');
    throw e;
  }
}));

r.post('/login', wrap(async (req, res) => {
  const b = loginSchema.parse(req.body);
  const { rows } = await query('SELECT * FROM users WHERE phone = $1', [b.phone]);
  const u = rows[0];
  if (!u || !(await bcrypt.compare(b.password, u.password_hash))) {
    throw new AppError(401, 'identifiants_incorrects', 'Numéro ou mot de passe incorrect');
  }
  res.json({ token: sign(u), user: publicUser(u) });
}));

r.get('/me', requireAuth, wrap(async (req, res) => {
  const { rows } = await query(
    `SELECT count(*)::int AS reports,
            count(*) FILTER (WHERE d.status IN ('verified','scheduled','cleaned'))::int AS verified,
            count(*) FILTER (WHERE d.status = 'cleaned')::int AS cleaned
     FROM reports r LEFT JOIN dumps d ON d.id = r.dump_id WHERE r.user_id = $1 AND r.status <> 'rejected'`,
    [req.user.id],
  );
  const s = rows[0];
  const badges = [];
  if (s.reports >= 1) badges.push({ id: 'premier_signalement', label: 'Premier signalement' });
  if (s.verified >= 5) badges.push({ id: 'oeil_de_quartier', label: 'Œil de quartier' });
  if (s.verified >= 25) badges.push({ id: 'sentinelle', label: 'Sentinelle' });
  if (s.cleaned >= 5) badges.push({ id: 'effet_visible', label: 'Effet visible' });
  res.json({ user: publicUser(req.user), stats: s, badges });
}));

export default r;
