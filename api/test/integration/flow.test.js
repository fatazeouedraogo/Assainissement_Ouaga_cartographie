import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { after, before, test } from 'node:test';
import { fileURLToPath } from 'node:url';

process.env.DATABASE_URL = process.env.TEST_DATABASE_URL || 'postgres://ouaga:ouaga@localhost:5432/ouaga_test';
process.env.UPLOAD_DIR = path.join(process.env.TMPDIR || '/tmp', 'ouaga-test-uploads');

const { migrate } = await import('../../src/migrate.js');
const { pool, query } = await import('../../src/db.js');
const { createApp } = await import('../../src/app.js');

const fx = (n) => fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'fixtures', `${n}.jpg`));
let base;
let server;
const tokens = {};

async function api(method, url, { token, json, form } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  let body;
  if (json) {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify(json);
  } else if (form) body = form;
  const res = await fetch(base + url, { method, headers, body });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

function reportForm(photo, { lat, lon, size = 'medium', clientId = crypto.randomUUID() }) {
  const f = new FormData();
  f.append('client_id', clientId);
  f.append('lat', String(lat));
  f.append('lon', String(lon));
  f.append('accuracy_m', '10');
  f.append('size', size);
  f.append('waste_type', 'household');
  if (photo) f.append('photo', new Blob([fx(photo)], { type: 'image/jpeg' }), 'p.jpg');
  return f;
}

before(async () => {
  await query('DROP SCHEMA public CASCADE');
  await query('CREATE SCHEMA public');
  await migrate(() => {});
  server = createApp().listen(0);
  base = `http://localhost:${server.address().port}`;
  for (const n of ['c1', 'c2', 'c3', 'adm']) {
    const r = await api('POST', '/api/auth/register', { json: { name: `Utilisateur ${n}`, phone: `+2267000${Math.floor(1000 + Math.random() * 8999)}`, password: 'secret123' } });
    assert.equal(r.status, 201);
    tokens[n] = r.body.token;
    if (n === 'adm') await query("UPDATE users SET role = 'admin' WHERE id = $1", [r.body.user.id]);
  }
});

after(async () => {
  server.close();
  await pool.end();
});

const A = { lat: 12.3714, lon: -1.5197 };
let dumpId;

test('signalement accepté puis doublon du même auteur rejeté', async () => {
  const r1 = await api('POST', '/api/reports', { token: tokens.c1, form: reportForm('a', A) });
  assert.equal(r1.status, 201);
  assert.equal(r1.body.report.status, 'accepted');
  assert.equal(r1.body.dump.status, 'pending');
  assert.equal(r1.body.points_awarded, 10);
  dumpId = r1.body.dump.id;
  const r2 = await api('POST', '/api/reports', { token: tokens.c1, form: reportForm('b', { lat: A.lat + 0.00005, lon: A.lon }) });
  assert.equal(r2.body.report.status, 'rejected');
  assert.ok(r2.body.report.reject_reasons.includes('doublon_meme_auteur'));
});

test('rejeu avec le même client_id idempotent', async () => {
  const id = crypto.randomUUID();
  const a = await api('POST', '/api/reports', { token: tokens.c2, form: reportForm('b', { lat: A.lat + 0.00006, lon: A.lon, clientId: id }) });
  const b = await api('POST', '/api/reports', { token: tokens.c2, form: reportForm('b', { lat: A.lat + 0.00006, lon: A.lon, clientId: id }) });
  assert.equal(a.status, 201);
  assert.equal(b.status, 200);
  assert.equal(b.body.duplicate, true);
  assert.equal(a.body.report.id, b.body.report.id);
});

test('recoupement : trois auteurs vérifient automatiquement le dépotoir', async () => {
  const r3 = await api('POST', '/api/reports', { token: tokens.c3, form: reportForm('c', { lat: A.lat, lon: A.lon + 0.00006 }) });
  assert.equal(r3.body.dump.id, dumpId);
  assert.equal(r3.body.dump.reporter_count, 3);
  assert.equal(r3.body.dump.status, 'verified');
  const me = await api('GET', '/api/auth/me', { token: tokens.c1 });
  assert.ok(me.body.user.points >= 30);
});

test('photo réutilisée ailleurs et hors zone rejetées', async () => {
  const far = await api('POST', '/api/reports', { token: tokens.c2, form: reportForm('a', { lat: 12.42, lon: -1.45 }) });
  assert.ok(far.body.report.reject_reasons.includes('photo_reutilisee'));
  const out = await api('POST', '/api/reports', { token: tokens.c2, form: reportForm('d', { lat: 14.0, lon: -1.5 }) });
  assert.ok(out.body.report.reject_reasons.includes('hors_zone'));
  const none = await api('POST', '/api/reports', { token: tokens.c2, form: reportForm(null, { lat: 12.40, lon: -1.50 }) });
  assert.ok(none.body.report.reject_reasons.includes('photo_absente'));
});

test('validation des champs', async () => {
  const f = reportForm('d', { lat: 12.4, lon: -1.5 });
  f.set('size', 'enorme');
  const r = await api('POST', '/api/reports', { token: tokens.c2, form: f });
  assert.equal(r.status, 422);
  assert.ok(r.body.fields.some((x) => x.field === 'size'));
});

test('droits : un citoyen ne peut pas planifier', async () => {
  const r = await api('POST', '/api/plan', { token: tokens.c1, json: {} });
  assert.equal(r.status, 403);
});

test('plan et simulation avec le moteur', async (t) => {
  const items = [];
  for (let i = 0; i < 600; i++) items.push({ lat: 12.37 + (Math.random() - 0.5) * 0.04, lon: -1.52 + (Math.random() - 0.5) * 0.04, narrow: i % 9 === 0 });
  const imp = await api('POST', '/api/buildings/bulk', { token: tokens.adm, json: { items, source: 'test' } });
  assert.equal(imp.status, 201);
  await api('POST', '/api/poi/bulk', { token: tokens.adm, json: { items: [{ kind: 'school', lat: 12.3715, lon: -1.5198 }, { kind: 'drain', lat: 12.3716, lon: -1.5196 }] } });
  const pr = await api('POST', '/api/dumps/recompute-priority', { token: tokens.adm, json: {} });
  if (pr.status === 503) return t.skip('moteur FastAPI indisponible');
  assert.equal(pr.status, 200);
  const list = await api('GET', '/api/dumps/priorities', { token: tokens.adm });
  assert.ok(list.body.items[0].priority_score > 0);
  const plan = await api('POST', '/api/plan', { token: tokens.adm, json: { params: { replications: 4, trucks: 4 }, time_limit_s: 2 } });
  assert.equal(plan.status, 200);
  assert.ok(plan.body.plan.points.length > 0);
  assert.ok(plan.body.warnings.includes('depot_a_renseigner'));
  const ev = await api('POST', '/api/plan', { token: tokens.adm, json: { params: { replications: 4, trucks: 4 }, events: [{ kind: 'rain_season' }], time_limit_s: 2 } });
  assert.ok(ev.body.simulation.summary.leakage_rate.mean > plan.body.simulation.summary.leakage_rate.mean);
});

test('cycle complet : programmation, nettoyage, récidive', async () => {
  const bad = await api('POST', `/api/dumps/${dumpId}/schedule`, { token: tokens.c1, json: { date: '2026-12-01' } });
  assert.equal(bad.status, 403);
  const sch = await api('POST', `/api/dumps/${dumpId}/schedule`, { token: tokens.adm, json: { date: '2026-12-01' } });
  assert.equal(sch.status, 200);
  const noPhoto = await api('POST', `/api/dumps/${dumpId}/clean`, { token: tokens.adm });
  assert.equal(noPhoto.status, 422);
  const f = new FormData();
  f.append('photo', new Blob([fx('d')], { type: 'image/jpeg' }), 'after.jpg');
  const clean = await api('POST', `/api/dumps/${dumpId}/clean`, { token: tokens.adm, form: f });
  assert.equal(clean.status, 200);
  const again = await api('POST', '/api/reports', { token: tokens.adm, form: reportForm('d', { lat: A.lat + 0.00003, lon: A.lon, size: 'large' }) });
  assert.equal(again.status, 201);
  assert.notEqual(again.body.dump.id, dumpId);
  const rec = await query('SELECT recurrence_of FROM dumps WHERE id = $1', [again.body.dump.id]);
  assert.equal(rec.rows[0].recurrence_of, dumpId);
});

test('tableau de bord public sans connexion', async () => {
  const o = await api('GET', '/api/public/overview');
  assert.equal(o.status, 200);
  assert.ok(o.body.by_status.cleaned.count >= 1);
  assert.ok(o.body.recurrence_rate > 0);
  const g = await api('GET', '/api/public/dumps.geojson');
  assert.equal(g.body.type, 'FeatureCollection');
  const l = await api('GET', '/api/public/leaderboard');
  assert.ok(l.body.leaders.length > 0);
});

test('notifications envoyées aux auteurs', async () => {
  const r = await api('GET', '/api/notifications', { token: tokens.c1 });
  assert.equal(r.status, 200);
  const kinds = r.body.items.map((n) => n.kind);
  assert.ok(kinds.includes('verified') && kinds.includes('scheduled') && kinds.includes('cleaned'));
  assert.ok(r.body.unread >= 3);
  await api('POST', '/api/notifications/read', { token: tokens.c1, json: {} });
  assert.equal((await api('GET', '/api/notifications', { token: tokens.c1 })).body.unread, 0);
});

test('capteur IoT : lecture, clé invalide, alerte de remplissage', async () => {
  const c = await api('POST', '/api/iot/sensors', { token: tokens.adm, json: { id: 'cont-001', name: 'Marché Rood Woko', lat: 12.37, lon: -1.52, height_cm: 100, min_cm: 10 } });
  assert.equal(c.status, 201);
  const bad = await fetch(`${base}/api/iot/readings`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Device-Key': 'faux' }, body: JSON.stringify({ sensor_id: 'cont-001', distance_cm: 30 }) });
  assert.equal(bad.status, 401);
  const ok = await fetch(`${base}/api/iot/readings`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Device-Key': c.body.secret }, body: JSON.stringify({ sensor_id: 'cont-001', distance_cm: 20 }) });
  assert.equal(ok.status, 201);
  const st = await api('GET', '/api/iot/status', { token: tokens.adm });
  assert.equal(st.body.sensors[0].urgent, true);
});

test('abonnement : paiement simulé clairement signalé', async () => {
  const p = await api('GET', '/api/subscriptions/price');
  assert.equal(p.body.simulated, true);
  const r = await api('POST', '/api/subscriptions/pay', { token: tokens.c1, json: { provider: 'orange', wallet_phone: '+22670112233', months: 3 } });
  assert.equal(r.status, 201);
  assert.equal(r.body.amount, p.body.price_month * 3);
  assert.ok(r.body.reference.startsWith('SIM-') && r.body.simulated);
  const mine = await api('GET', '/api/subscriptions/mine', { token: tokens.c1 });
  assert.ok(mine.body.active_until);
});

test('WhatsApp : position puis photo créent un signalement', async () => {
  const { handleMessage, parseMessages, verifySignature } = await import('../../src/services/whatsapp.js');
  const sent = [];
  const deps = { fetchMedia: async () => ({ buffer: fx('e'), mime: 'image/jpeg' }), reply: async (to, text) => sent.push(text) };
  const from = '22670998877';
  await handleMessage({ from, type: 'image', mediaId: 'x' }, deps);
  assert.match(sent.at(-1), /position/i);
  await handleMessage({ from, type: 'location', lat: 12.4, lon: -1.55 }, deps);
  await handleMessage({ from, type: 'text', text: 'gros tas' }, deps);
  await handleMessage({ from, type: 'image', mediaId: 'x' }, deps);
  assert.match(sent.at(-1), /signalement reçu/);
  const row = await query("SELECT r.size FROM reports r JOIN users u ON u.id = r.user_id WHERE u.phone = '+22670998877'");
  assert.equal(row.rows[0].size, 'large');
  const payload = { entry: [{ changes: [{ value: { messages: [{ from, id: '1', type: 'location', location: { latitude: 1, longitude: 2 } }] } }] }] };
  assert.equal(parseMessages(payload)[0].lat, 1);
  const body = Buffer.from('{}');
  const sig = 'sha256=' + (await import('node:crypto')).createHmac('sha256', 's3cret').update(body).digest('hex');
  assert.equal(verifySignature(body, sig, 's3cret'), true);
  assert.equal(verifySignature(body, 'sha256=00', 's3cret'), false);
});

test('page publique et webhook protégé', async () => {
  const page = await fetch(base + '/');
  assert.equal(page.status, 200);
  assert.match(await page.text(), /Ouaga Propre/);
  assert.equal((await fetch(`${base}/api/whatsapp/webhook`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })).status, 401);
  assert.equal((await fetch(`${base}/api/whatsapp/webhook?hub.mode=subscribe&hub.verify_token=x&hub.challenge=1`)).status, 403);
});

test('assistant, recommandation, PDF, risque, compromis (moteur requis)', async (t) => {
  const ask = await api('POST', '/api/insights/ask', { token: tokens.adm, json: { question: 'Et si on avait 3 camions de plus pendant la saison des pluies ?' } });
  if (ask.status === 503) return t.skip('moteur indisponible');
  assert.equal(ask.status, 200);
  assert.match(ask.body.answer, /collecte passe de/);
  const unknown = await api('POST', '/api/insights/ask', { token: tokens.adm, json: { question: 'bonjour tout le monde' } });
  assert.equal(unknown.status, 422);
  const rec = await api('POST', '/api/insights/recommend', { token: tokens.adm, json: { params: { trucks: 3 }, events: [{ kind: 'truck_breakdown', value: 1 }] } });
  assert.equal(rec.status, 200);
  assert.ok(rec.body.best);
  const risk = await api('GET', '/api/insights/risk', { token: tokens.c1 });
  assert.equal(risk.status, 200);
  assert.ok(risk.body.cells.length > 0);
  const par = await api('POST', '/api/insights/pareto', { token: tokens.adm, json: {} });
  assert.ok(par.body.points.some((p) => p.pareto));
  const pdf = await fetch(`${base}/api/insights/report.pdf`, { method: 'POST', headers: { Authorization: `Bearer ${tokens.adm}`, 'Content-Type': 'application/json' }, body: '{}' });
  assert.equal(pdf.status, 200);
  const buf = Buffer.from(await pdf.arrayBuffer());
  assert.equal(buf.subarray(0, 4).toString(), '%PDF');
  assert.ok(buf.length > 2500);
});

test('candidats satellite : analyse, validation terrain, statistiques, seuil', async (t) => {
  const tile = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'fixtures', 'tile.png'));
  const f = new FormData();
  f.append('image', new Blob([tile], { type: 'image/png' }), 'tile.png');
  for (const [k, v] of Object.entries({ south: 12.3, west: -1.6, north: 12.4, east: -1.5 })) f.append(k, String(v));
  const scan = await api('POST', '/api/candidates/scan', { token: tokens.adm, form: f });
  if (scan.status === 503) return t.skip('moteur indisponible');
  assert.equal(scan.status, 201);
  assert.ok(scan.body.added >= 2);

  const citizen = await api('GET', '/api/candidates', { token: tokens.c1 });
  assert.equal(citizen.status, 403);

  const list = await api('GET', '/api/candidates', { token: tokens.adm });
  assert.ok(list.body.candidates.length >= 2);
  assert.ok(list.body.candidates[0].signals.texture_z !== undefined);
  const [first, second] = list.body.candidates;

  const noReason = await api('POST', `/api/candidates/${second.id}/dismiss`, { token: tokens.adm, json: {} });
  assert.equal(noReason.status, 422);
  const badReason = await api('POST', `/api/candidates/${second.id}/dismiss`, { token: tokens.adm, json: { reason: 'au_hasard' } });
  assert.equal(badReason.status, 422);
  const dis = await api('POST', `/api/candidates/${second.id}/dismiss`, { token: tokens.adm, json: { reason: 'route', note: 'chaussée goudronnée' } });
  assert.equal(dis.status, 200);

  const conf = await api('POST', `/api/candidates/${first.id}/confirm`, { token: tokens.adm, json: { size: 'large' } });
  assert.equal(conf.status, 201);
  const dump = await query('SELECT status, size FROM dumps WHERE id = $1', [conf.body.dump_id]);
  assert.deepEqual(dump.rows[0], { status: 'verified', size: 'large' });
  const again = await api('POST', `/api/candidates/${first.id}/confirm`, { token: tokens.adm, json: {} });
  assert.equal(again.status, 409);

  const stats = await api('GET', '/api/candidates/stats', { token: tokens.adm });
  assert.equal(stats.body.confirmed, 1);
  assert.equal(stats.body.dismissed, 1);
  assert.equal(stats.body.precision, 0.5);
  assert.equal(stats.body.reject_reasons.route, 1);
  assert.match(stats.body.note, /Moins de 10/);

  const set = await api('PUT', '/api/settings/detection', { token: tokens.adm, json: { min_score: 4, merge_m: 30, risk_weight: 0.5 } });
  assert.equal(set.status, 200);
  assert.equal((await api('GET', '/api/candidates/stats', { token: tokens.adm })).body.current.min_score, 4);
  const bad = await api('PUT', '/api/settings/detection', { token: tokens.adm, json: { min_score: -1, merge_m: 30, risk_weight: 0.5 } });
  assert.equal(bad.status, 422);
});

test('exports ouverts : CSV, JOSM, datapackage', async () => {
  const csv = await (await fetch(`${base}/api/public/dumps.csv`)).text();
  assert.match(csv.split('\n')[0], /^id,lat,lon,status/);
  assert.ok(csv.split('\n').length > 1);
  const osm = await fetch(`${base}/api/public/dumps.osm`, { headers: { Authorization: `Bearer ${tokens.adm}` } });
  assert.equal(osm.status, 200);
  assert.match(await osm.text(), /<osm version="0.6"[\s\S]*waste_dump_site/);
  assert.equal((await fetch(`${base}/api/public/dumps.osm`)).status, 401);
  const dp = await (await fetch(`${base}/api/public/datapackage.json`)).json();
  assert.equal(dp.licenses[0].name, 'ODbL-1.0');
});

test('observations, calibration sur observation, apprentissage persistant, pré-collecteurs', async (t) => {
  const obs = await api('POST', '/api/insights/observations', { token: tokens.adm, json: { metric: 'collection_rate', value: 0.6, note: 'chiffre mairie (test)' } });
  assert.equal(obs.status, 201);
  assert.equal((await api('POST', '/api/insights/observations', { token: tokens.c1, json: { metric: 'collection_rate', value: 0.6 } })).status, 403);
  const cal = await api('POST', '/api/insights/calibrate', { token: tokens.adm, json: { metric: 'collection_rate', parameter: 'subscription_rate', low: 0.05, high: 0.95, params: { trucks: 1, precollectors: 30 } } });
  if (cal.status === 503) return t.skip('moteur indisponible');
  assert.equal(cal.status, 200);
  assert.equal(cal.body.target, 0.6);

  const body = { params: { trucks: 3 }, events: [{ kind: 'truck_breakdown', value: 1 }], episodes: 20 };
  const l1 = await api('POST', '/api/insights/learn', { token: tokens.adm, json: body });
  assert.equal(l1.status, 200);
  const l2 = await api('POST', '/api/insights/learn', { token: tokens.adm, json: body });
  const total = (r) => r.body.policy.reduce((a, p) => a + p.pulls, 0);
  assert.ok(total(l2) > total(l1));
  const rows = await query('SELECT count(*)::int AS n FROM rl_state WHERE context = $1', [l1.body.context]);
  assert.ok(rows.rows[0].n >= 5);

  const pc = await api('POST', '/api/insights/precollectors', { token: tokens.adm, json: { params: { precollectors: 5 } } });
  assert.equal(pc.status, 200);
  assert.ok(pc.body.precollectors.length > 0 && pc.body.precollectors[0].revenue_month > 0);
  const plan = await api('POST', '/api/plan', { token: tokens.adm, json: { params: { replications: 3 }, time_limit_s: 2 } });
  assert.ok('urgent_points' in plan.body.plan.metrics);
});
