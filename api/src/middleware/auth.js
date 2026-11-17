import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { query } from '../db.js';
import { AppError } from './errors.js';

export function sign(user) {
  return jwt.sign({ sub: user.id, role: user.role }, config.jwtSecret, { expiresIn: '30d' });
}

async function load(req) {
  const h = req.headers.authorization || '';
  if (!h.startsWith('Bearer ')) return null;
  let payload;
  try {
    payload = jwt.verify(h.slice(7), config.jwtSecret);
  } catch {
    throw new AppError(401, 'session_invalide', 'Session expirée ou invalide');
  }
  const { rows } = await query('SELECT id, name, phone, role, points FROM users WHERE id = $1', [payload.sub]);
  return rows[0] || null;
}

export async function requireAuth(req, _res, next) {
  try {
    const u = await load(req);
    if (!u) throw new AppError(401, 'non_connecte', 'Connexion requise');
    req.user = u;
    next();
  } catch (e) {
    next(e);
  }
}

export async function optionalAuth(req, _res, next) {
  try {
    req.user = await load(req);
    next();
  } catch (e) {
    next(e);
  }
}

export const requireRole = (...roles) => (req, _res, next) =>
  roles.includes(req.user?.role) ? next() : next(new AppError(403, 'acces_refuse', 'Droits insuffisants'));
