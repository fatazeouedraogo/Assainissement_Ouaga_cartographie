import cors from 'cors';
import express from 'express';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from './config.js';
import { errorHandler, notFound } from './middleware/errors.js';
import auth from './routes/auth.js';
import dumps from './routes/dumps.js';
import { buildings, plan, poi, scenarios, settings } from './routes/ops.js';
import publicRoutes from './routes/public.js';
import reports from './routes/reports.js';
import { candidates, insights, iot, notifications, subscriptions, whatsappRoutes } from './routes/extras.js';

export function createApp() {
  const app = express();
  app.set('trust proxy', 1);
  app.use(
    helmet({
      crossOriginResourcePolicy: { policy: 'cross-origin' },
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          scriptSrc: ["'self'", 'https://cdnjs.cloudflare.com'],
          styleSrc: ["'self'", "'unsafe-inline'", 'https://cdnjs.cloudflare.com'],
          imgSrc: ["'self'", 'data:', 'https://tile.openstreetmap.org', 'https://cdnjs.cloudflare.com'],
          connectSrc: ["'self'"],
        },
      },
    }),
  );
  app.use(cors({ origin: config.corsOrigins.includes('*') ? true : config.corsOrigins }));
  app.use(express.json({ limit: '2mb', verify: (req, _res, buf) => { req.rawBody = buf; } }));

  app.get('/health', (_req, res) => res.json({ status: 'ok' }));
  app.use('/uploads', express.static(path.resolve(config.uploadDir), { maxAge: '7d', index: false }));

  const strict = rateLimit({ windowMs: 15 * 60 * 1000, limit: 40, standardHeaders: true, legacyHeaders: false });
  const normal = rateLimit({ windowMs: 60 * 1000, limit: 240, standardHeaders: true, legacyHeaders: false });
  app.use('/api', normal);
  app.use('/api/auth', strict, auth);
  app.use('/api/reports', reports);
  app.use('/api/dumps', dumps);
  app.use('/api/plan', plan);
  app.use('/api/scenarios', scenarios);
  app.use('/api/poi', poi);
  app.use('/api/buildings', buildings);
  app.use('/api/settings', settings);
  app.use('/api/public', publicRoutes);
  app.use('/api/insights', insights);
  app.use('/api/notifications', notifications);
  app.use('/api/iot', iot);
  app.use('/api/candidates', candidates);
  app.use('/api/subscriptions', subscriptions);
  app.use('/api/whatsapp', whatsappRoutes);
  app.use(express.static(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'public'), { index: 'index.html' }));

  app.use(notFound);
  app.use(errorHandler);
  return app;
}
