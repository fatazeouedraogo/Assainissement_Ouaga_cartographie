import bcrypt from 'bcryptjs';
import { migrate } from '../src/migrate.js';
import { pool, query } from '../src/db.js';

const CENTERS = [
  [12.3714, -1.5197, 0.018, 700, false],
  [12.3900, -1.5000, 0.012, 450, true],
  [12.3500, -1.5400, 0.014, 450, false],
  [12.4100, -1.5500, 0.016, 350, false],
  [12.3300, -1.4900, 0.015, 350, true],
  [12.3800, -1.4600, 0.013, 300, false],
];

function gauss() {
  return Math.sqrt(-2 * Math.log(1 - Math.random())) * Math.cos(2 * Math.PI * Math.random());
}

async function user(name, phone, role, password) {
  const hash = await bcrypt.hash(password, 10);
  await query(
    `INSERT INTO users (name, phone, password_hash, role) VALUES ($1, $2, $3, $4)
     ON CONFLICT (phone) DO UPDATE SET role = EXCLUDED.role`,
    [name, phone, hash, role],
  );
}

await migrate();
const pw = process.env.SEED_PASSWORD || 'demo-2026';
await user('Administration Mairie', '+22670000001', 'admin', pw);
await user('Vérificateur Secteur 12', '+22670000002', 'verifier', pw);
await user('Agent Terrain', '+22670000003', 'agent', pw);

const exists = await query("SELECT count(*)::int AS n FROM buildings WHERE source = 'synthetic'");
if (!exists.rows[0].n) {
  const la = [], lo = [], nr = [];
  for (const [clat, clon, sd, n, narrow] of CENTERS) {
    for (let i = 0; i < n; i++) {
      la.push(clat + gauss() * sd);
      lo.push(clon + gauss() * sd);
      nr.push(narrow);
    }
  }
  await query(
    `INSERT INTO buildings (geom, weight, narrow, source)
     SELECT ST_SetSRID(ST_MakePoint(lo, la), 4326)::geography, 1, nr, 'synthetic'
     FROM unnest($1::float8[], $2::float8[], $3::boolean[]) AS t(la, lo, nr)`,
    [la, lo, nr],
  );
  console.log(`${la.length} bâtiments synthétiques créés (à remplacer par Open Buildings)`);
}
console.log(`Comptes de démonstration : +22670000001 (admin), +22670000002 (vérificateur), +22670000003 (agent), mot de passe : ${pw}`);
await pool.end();
