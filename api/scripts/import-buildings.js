import fs from 'node:fs';
import readline from 'node:readline';

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? process.argv[i + 1] : fallback;
}

export function parseCsvLine(line) {
  const out = [];
  let cur = '';
  let q = false;
  for (const ch of line) {
    if (ch === '"') q = !q;
    else if (ch === ',' && !q) {
      out.push(cur);
      cur = '';
    } else cur += ch;
  }
  out.push(cur);
  return out;
}

export function rowFilter({ bbox, minConfidence }) {
  return (lat, lon, conf) => {
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) return false;
    if (bbox && (lat < bbox[0] || lat > bbox[2] || lon < bbox[1] || lon > bbox[3])) return false;
    if (Number.isFinite(conf) && conf < minConfidence) return false;
    return true;
  };
}

async function main() {
  const api = (arg('api', 'http://localhost:3000')).replace(/\/+$/, '');
  const file = arg('csv');
  if (!file) {
    console.error('Usage : node scripts/import-buildings.js --csv fichier.csv --phone +226... --password ... [--api http://localhost:3000] [--bbox sud,ouest,nord,est] [--min-confidence 0.7] [--source open_buildings]');
    process.exit(1);
  }
  const bbox = arg('bbox')?.split(',').map(Number);
  const keep = rowFilter({ bbox, minConfidence: Number(arg('min-confidence', '0.7')) });
  const source = arg('source', 'open_buildings');

  let token = arg('token');
  if (!token) {
    const res = await fetch(`${api}/api/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ phone: arg('phone'), password: arg('password') }) });
    if (!res.ok) throw new Error(`connexion refusée (${res.status})`);
    token = (await res.json()).token;
  }

  const rl = readline.createInterface({ input: fs.createReadStream(file), crlfDelay: Infinity });
  let cols = null;
  let batch = [];
  let sent = 0;
  let skipped = 0;
  const flush = async () => {
    if (!batch.length) return;
    const res = await fetch(`${api}/api/buildings/bulk`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: JSON.stringify({ items: batch, source }) });
    if (!res.ok) throw new Error(`import refusé (${res.status}) : ${await res.text()}`);
    sent += batch.length;
    batch = [];
    process.stdout.write(`\r${sent} bâtiments importés`);
  };

  for await (const line of rl) {
    if (!line.trim()) continue;
    const parts = parseCsvLine(line);
    if (!cols) {
      cols = parts.map((c) => c.trim().toLowerCase());
      const need = (names) => names.map((n) => cols.indexOf(n)).find((i) => i >= 0) ?? -1;
      cols = { lat: need(['latitude', 'lat']), lon: need(['longitude', 'lon', 'lng']), conf: need(['confidence']) };
      if (cols.lat < 0 || cols.lon < 0) throw new Error('colonnes latitude et longitude introuvables');
      continue;
    }
    const lat = Number(parts[cols.lat]);
    const lon = Number(parts[cols.lon]);
    const conf = cols.conf >= 0 ? Number(parts[cols.conf]) : NaN;
    if (!keep(lat, lon, conf)) {
      skipped++;
      continue;
    }
    batch.push({ lat, lon, weight: 1, narrow: false });
    if (batch.length === 5000) await flush();
  }
  await flush();
  console.log(`\nTerminé : ${sent} importés, ${skipped} ignorés (hors emprise ou confiance trop faible).`);
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop())) {
  main().catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}
