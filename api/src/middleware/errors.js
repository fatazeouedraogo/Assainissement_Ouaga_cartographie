import { ZodError } from 'zod';

export class AppError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

export const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

export function notFound(_req, _res, next) {
  next(new AppError(404, 'introuvable', 'Route inconnue'));
}

export function errorHandler(err, _req, res, _next) {
  if (err instanceof ZodError) {
    return res.status(422).json({
      error: 'donnees_invalides',
      message: 'Certains champs sont invalides',
      fields: err.issues.map((i) => ({ field: i.path.join('.'), message: i.message })),
    });
  }
  if (err instanceof AppError) {
    return res.status(err.status).json({ error: err.code, message: err.message, details: err.details });
  }
  if (err.code === 'LIMIT_FILE_SIZE') {
    return res.status(413).json({ error: 'photo_trop_lourde', message: 'La photo dépasse 8 Mo' });
  }
  if (err.code === '23505') {
    return res.status(409).json({ error: 'conflit', message: 'Cet enregistrement existe déjà' });
  }
  console.error(err);
  res.status(500).json({ error: 'erreur_interne', message: 'Erreur interne du serveur' });
}
