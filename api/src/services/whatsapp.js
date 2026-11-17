import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import { whatsapp } from '../config.js';
import { query } from '../db.js';
import { rejectText, flagText } from './messages.js';
import { submitReport } from './reports.js';

export function verifySignature(rawBody, header, secret = whatsapp.appSecret) {
  if (!secret) return false;
  const expected = 'sha256=' + crypto.createHmac('sha256', secret).update(rawBody).digest('hex');
  const a = Buffer.from(expected);
  const b = Buffer.from(header || '');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export function parseMessages(payload) {
  const out = [];
  for (const entry of payload?.entry || []) {
    for (const change of entry.changes || []) {
      for (const m of change.value?.messages || []) {
        const base = { from: m.from, id: m.id, type: m.type };
        if (m.type === 'text') out.push({ ...base, text: m.text?.body || '' });
        else if (m.type === 'location') out.push({ ...base, lat: m.location.latitude, lon: m.location.longitude });
        else if (m.type === 'image') out.push({ ...base, mediaId: m.image.id });
        else out.push(base);
      }
    }
  }
  return out;
}

async function userFor(phone) {
  const full = phone.startsWith('+') ? phone : `+${phone}`;
  const found = await query('SELECT id, name, phone, role, points FROM users WHERE phone = $1', [full]);
  if (found.rows[0]) return found.rows[0];
  const hash = await bcrypt.hash(crypto.randomBytes(18).toString('hex'), 8);
  const ins = await query(
    'INSERT INTO users (name, phone, password_hash) VALUES ($1, $2, $3) RETURNING id, name, phone, role, points',
    [`WhatsApp ${full.slice(-4)}`, full, hash],
  );
  return ins.rows[0];
}

const HELP = 'Pour signaler un dépotoir : 1) envoyez votre position (pièce jointe > Position), 2) envoyez une photo. Vous pouvez écrire « petit », « moyen » ou « gros » avant la photo.';

export async function handleMessage(msg, deps) {
  const { fetchMedia, reply } = deps;
  const user = await userFor(msg.from);
  const sizeWord = (t) => (/\bpetit\b/i.test(t) ? 'small' : /\b(gros|grand|enorme|énorme)\b/i.test(t) ? 'large' : /\bmoyen\b/i.test(t) ? 'medium' : null);

  if (msg.type === 'text') {
    const size = sizeWord(msg.text);
    if (size) {
      await query(
        `INSERT INTO chat_sessions (phone, size) VALUES ($1, $2)
         ON CONFLICT (phone) DO UPDATE SET size = $2, updated_at = now()`,
        [msg.from, size],
      );
      return reply(msg.from, 'Taille enregistrée. Envoyez la photo du dépotoir.');
    }
    return reply(msg.from, HELP);
  }

  if (msg.type === 'location') {
    await query(
      `INSERT INTO chat_sessions (phone, lat, lon) VALUES ($1, $2, $3)
       ON CONFLICT (phone) DO UPDATE SET lat = $2, lon = $3, updated_at = now()`,
      [msg.from, msg.lat, msg.lon],
    );
    return reply(msg.from, 'Position reçue. Envoyez maintenant la photo du dépotoir.');
  }

  if (msg.type === 'image') {
    const { rows } = await query("SELECT * FROM chat_sessions WHERE phone = $1 AND updated_at > now() - interval '30 minutes'", [msg.from]);
    const sess = rows[0];
    if (!sess || sess.lat == null) return reply(msg.from, 'Envoyez d’abord votre position, puis la photo.');
    const media = await fetchMedia(msg.mediaId);
    const out = await submitReport({
      user,
      fields: {
        client_id: crypto.randomUUID(),
        lat: sess.lat,
        lon: sess.lon,
        size: sess.size || 'medium',
        waste_type: 'mixed',
        captured_at: new Date().toISOString(),
      },
      photoBuffer: media.buffer,
      photoMime: media.mime,
    });
    await query('DELETE FROM chat_sessions WHERE phone = $1', [msg.from]);
    const rep = out.report;
    if (rep.status === 'rejected') return reply(msg.from, `Signalement refusé : ${rep.reject_reasons.map(rejectText).join(', ')}.`);
    const extra = rep.flags.length ? ` À contrôler : ${rep.flags.map(flagText).join(', ')}.` : '';
    return reply(msg.from, `Merci, signalement reçu (+${out.points || 0} points).${extra}`);
  }
  return reply(msg.from, HELP);
}

export const graph = {
  async fetchMedia(mediaId) {
    const h = { Authorization: `Bearer ${whatsapp.token}` };
    const meta = await (await fetch(`https://graph.facebook.com/v20.0/${mediaId}`, { headers: h })).json();
    const res = await fetch(meta.url, { headers: h });
    return { buffer: Buffer.from(await res.arrayBuffer()), mime: res.headers.get('content-type') || 'image/jpeg' };
  },
  async reply(to, body) {
    if (!whatsapp.token || !whatsapp.phoneId) return;
    await fetch(`https://graph.facebook.com/v20.0/${whatsapp.phoneId}/messages`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${whatsapp.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ messaging_product: 'whatsapp', to, type: 'text', text: { body } }),
    });
  },
};
