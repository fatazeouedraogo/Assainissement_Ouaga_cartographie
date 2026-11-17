import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { config } from '../config.js';
import { query, tx } from '../db.js';
import { engine } from './engine.js';
import { notifyAuthors } from './notify.js';
import { SIZE_KG, DUP_RADIUS_M, PHOTO_COPY_HAMMING, combineConfidence, dumpStatusFor, evaluateReport, hexToBits, medianSize, trustOf } from './rules.js';

const pointSql = (a, b) => `ST_SetSRID(ST_MakePoint($${a}, $${b}), 4326)::geography`;

export async function getThresholds() {
  const { rows } = await query("SELECT value FROM settings WHERE key = 'thresholds'");
  return rows[0].value;
}

export function savePhoto(buffer) {
  fs.mkdirSync(config.uploadDir, { recursive: true });
  const name = `${crypto.randomUUID()}.jpg`;
  fs.writeFileSync(path.join(config.uploadDir, name), buffer);
  return name;
}

export async function recomputeDump(client, dumpId) {
  const { rows } = await client.query(
    `SELECT user_id, size, waste_type, credibility, created_at FROM reports
     WHERE dump_id = $1 AND status <> 'rejected' ORDER BY created_at`,
    [dumpId],
  );
  const perUser = new Map();
  for (const r of rows) perUser.set(r.user_id, Math.max(perUser.get(r.user_id) || 0, r.credibility));
  const confidence = combineConfidence([...perUser.values()]);
  const size = medianSize(rows.map((r) => r.size));
  const types = rows.map((r) => r.waste_type);
  const wasteType = types.sort((a, b) => types.filter((x) => x === b).length - types.filter((x) => x === a).length)[0] || 'mixed';
  const thresholds = (await client.query("SELECT value FROM settings WHERE key = 'thresholds'")).rows[0].value;
  const cur = (await client.query('SELECT status FROM dumps WHERE id = $1', [dumpId])).rows[0].status;
  const status = dumpStatusFor({ confidence, reporters: perUser.size, current: cur, thresholds });
  await client.query(
    `UPDATE dumps SET confidence = $2, reporter_count = $3, report_count = $4, size = $5, waste_type = $6,
       est_kg = $7, status = $8::dump_status, last_reported_at = now(),
       verified_at = CASE WHEN $8::dump_status = 'verified' AND verified_at IS NULL THEN now() ELSE verified_at END
     WHERE id = $1`,
    [dumpId, confidence, perUser.size, rows.length, size, wasteType, SIZE_KG[size], status],
  );
  return status;
}

export async function award(client, userId, dumpId, reason, delta) {
  const r = await client.query(
    'INSERT INTO point_ledger (user_id, dump_id, reason, delta) VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING RETURNING id',
    [userId, dumpId, reason, delta],
  );
  if (r.rowCount) await client.query('UPDATE users SET points = points + $2 WHERE id = $1', [userId, delta]);
  return r.rowCount ? delta : 0;
}

export async function awardVerified(client, dumpId) {
  const { rows } = await client.query(
    "SELECT DISTINCT user_id FROM reports WHERE dump_id = $1 AND status <> 'rejected'",
    [dumpId],
  );
  for (const r of rows) await award(client, r.user_id, dumpId, 'dump_verified', 20);
}

export async function submitReport({ user, fields, photoBuffer, photoMime }) {
  const existing = await query('SELECT * FROM reports WHERE client_id = $1', [fields.client_id]);
  if (existing.rows[0]) return { duplicate: true, report: existing.rows[0] };

  const analysis = photoBuffer ? await engine.analyzePhoto(photoBuffer, photoMime) : null;
  const { lat, lon } = fields;

  const [sameUser, matches, last, stats] = await Promise.all([
    query(
      `SELECT 1 FROM reports WHERE user_id = $1 AND status <> 'rejected' AND created_at > now() - interval '24 hours'
         AND ST_DWithin(geom, ${pointSql(2, 3)}, $4) LIMIT 1`,
      [user.id, lon, lat, DUP_RADIUS_M],
    ),
    analysis?.phash
      ? query(
          `SELECT user_id, ST_Distance(geom, ${pointSql(2, 3)}) AS d FROM reports
           WHERE photo_hash IS NOT NULL AND status <> 'rejected' AND bit_count(photo_hash # $1::bit(64)) <= $4`,
          [hexToBits(analysis.phash), lon, lat, PHOTO_COPY_HAMMING],
        )
      : { rows: [] },
    query(
      `SELECT ST_Distance(geom, ${pointSql(2, 3)}) AS d, EXTRACT(EPOCH FROM ($4::timestamptz - captured_at)) AS s
       FROM reports WHERE user_id = $1 AND status <> 'rejected' ORDER BY captured_at DESC LIMIT 1`,
      [user.id, lon, lat, fields.captured_at],
    ),
    query(
      `SELECT count(*) FILTER (WHERE d.status IN ('verified','scheduled','cleaned'))::int AS ok,
              count(*) FILTER (WHERE r.status = 'rejected' OR d.status = 'rejected')::int AS bad
       FROM reports r LEFT JOIN dumps d ON d.id = r.dump_id WHERE r.user_id = $1`,
      [user.id],
    ),
  ]);

  const verdict = evaluateReport({
    lat,
    lon,
    accuracyM: fields.accuracy_m,
    photo: { present: Boolean(photoBuffer), analysis },
    sameUserNearby: sameUser.rowCount > 0,
    photoMatches: matches.rows.map((m) => ({ distanceM: m.d, sameUser: m.user_id === user.id })),
    trust: trustOf(stats.rows[0].ok, stats.rows[0].bad),
    lastReport: last.rows[0] ? { distanceM: last.rows[0].d, seconds: last.rows[0].s } : null,
  });

  const photoName = photoBuffer ? savePhoto(photoBuffer) : null;
  const status = verdict.decision === 'reject' ? 'rejected' : verdict.decision === 'flag' ? 'flagged' : 'accepted';

  return tx(async (client) => {
    const ins = await client.query(
      `INSERT INTO reports (client_id, user_id, geom, accuracy_m, size, waste_type, note, photo_path, photo_hash,
         photo_analysis, credibility, status, flags, reject_reasons, captured_at)
       VALUES ($1, $2, ${pointSql(3, 4)}, $5, $6, $7, $8, $9, $10::bit(64), $11, $12, $13, $14, $15, $16)
       ON CONFLICT (client_id) DO NOTHING RETURNING id`,
      [
        fields.client_id,
        user.id,
        lon,
        lat,
        fields.accuracy_m ?? null,
        fields.size,
        fields.waste_type,
        fields.note ?? null,
        photoName,
        analysis?.phash ? hexToBits(analysis.phash) : null,
        analysis ? JSON.stringify(analysis) : null,
        verdict.credibility,
        status,
        verdict.flags,
        verdict.rejectReasons,
        fields.captured_at,
      ],
    );
    if (!ins.rowCount) {
      const again = await client.query('SELECT * FROM reports WHERE client_id = $1', [fields.client_id]);
      return { duplicate: true, report: again.rows[0] };
    }
    const reportId = ins.rows[0].id;
    let dumpId = null;
    let points = 0;

    if (status !== 'rejected') {
      const near = await client.query(
        `SELECT id FROM dumps WHERE status IN ('pending','verified','scheduled') AND ST_DWithin(geom, ${pointSql(1, 2)}, $3)
         ORDER BY ST_Distance(geom, ${pointSql(1, 2)}) LIMIT 1`,
        [lon, lat, DUP_RADIUS_M],
      );
      if (near.rows[0]) dumpId = near.rows[0].id;
      else {
        const rec = await client.query(
          `SELECT id FROM dumps WHERE status = 'cleaned' AND ST_DWithin(geom, ${pointSql(1, 2)}, $3) ORDER BY cleaned_at DESC LIMIT 1`,
          [lon, lat, DUP_RADIUS_M],
        );
        const created = await client.query(
          `INSERT INTO dumps (geom, size, waste_type, est_kg, before_photo, recurrence_of)
           VALUES (${pointSql(1, 2)}, $3, $4, $5, $6, $7) RETURNING id`,
          [lon, lat, fields.size, fields.waste_type, SIZE_KG[fields.size], photoName, rec.rows[0]?.id ?? null],
        );
        dumpId = created.rows[0].id;
      }
      await client.query('UPDATE reports SET dump_id = $2 WHERE id = $1', [reportId, dumpId]);
      let dstatus = await recomputeDump(client, dumpId);
      if (['verifier', 'admin'].includes(user.role) && dstatus === 'pending') {
        await client.query(
          "UPDATE dumps SET status = 'verified', verified_by = $2, verified_at = now() WHERE id = $1",
          [dumpId, user.id],
        );
        dstatus = 'verified';
      }
      points += await award(client, user.id, dumpId, `report:${reportId}`, 10);
      if (dstatus === 'verified') {
        await awardVerified(client, dumpId);
        await notifyAuthors(client, dumpId, 'verified', 'Dépotoir confirmé', 'Votre signalement a été confirmé. Il entre dans le plan de la ville.');
      }
    }

    const report = (await client.query('SELECT * FROM reports WHERE id = $1', [reportId])).rows[0];
    const dump = dumpId ? (await client.query('SELECT * FROM dumps WHERE id = $1', [dumpId])).rows[0] : null;
    return { duplicate: false, report, dump, points };
  });
}
