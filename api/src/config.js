import 'dotenv/config';

const isProd = process.env.NODE_ENV === 'production';

if (isProd && (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32)) {
  throw new Error('JWT_SECRET doit contenir au moins 32 caractères en production');
}

export const config = {
  port: Number(process.env.PORT || 3000),
  databaseUrl: process.env.DATABASE_URL || 'postgres://ouaga:ouaga@localhost:5432/ouaga',
  jwtSecret: process.env.JWT_SECRET || 'dev-secret-ne-pas-utiliser-en-production',
  engineUrl: process.env.ENGINE_URL || 'http://localhost:8000',
  engineKey: process.env.ENGINE_API_KEY || '',
  uploadDir: process.env.UPLOAD_DIR || './uploads',
  corsOrigins: (process.env.CORS_ORIGINS || '*').split(',').map((s) => s.trim()),
  publicBaseUrl: process.env.PUBLIC_BASE_URL || '',
  isProd,
};

const [bs, bw, bn, be] = (process.env.COMMUNE_BBOX || '12.25,-1.70,12.50,-1.35').split(',').map(Number);
export const OUAGA_BBOX = { south: bs, west: bw, north: bn, east: be };

export const whatsapp = {
  verifyToken: process.env.WHATSAPP_VERIFY_TOKEN || '',
  appSecret: process.env.WHATSAPP_APP_SECRET || '',
  token: process.env.WHATSAPP_TOKEN || '',
  phoneId: process.env.WHATSAPP_PHONE_ID || '',
};
