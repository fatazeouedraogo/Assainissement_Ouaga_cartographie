import { query } from '../db.js';

const CACHE_MS = 30 * 60 * 1000;
let cache = null;

export function assessRain(daily) {
  const mm = daily.precipitation_sum || [];
  const days = daily.time || [];
  const wetDays = mm.filter((v) => v >= 10).length;
  const peak = mm.reduce((a, b) => Math.max(a, b || 0), 0);
  const total = mm.reduce((a, b) => a + (b || 0), 0);
  const rainy = wetDays >= 3 || peak >= 40;
  return {
    rainy,
    wet_days: wetDays,
    peak_mm: Number(peak.toFixed(1)),
    total_mm: Number(total.toFixed(1)),
    days: days.map((d, i) => ({ date: d, mm: mm[i] ?? 0 })),
    rule: 'pluie forte : au moins 3 jours à 10 mm ou plus, ou un jour à 40 mm ou plus, sur les 7 prochains jours',
  };
}

export async function forecast(fetchImpl = fetch) {
  if (cache && Date.now() - cache.at < CACHE_MS) return cache.value;
  const { rows } = await query("SELECT value FROM settings WHERE key = 'depot'");
  const { lat, lon } = rows[0].value;
  const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&daily=precipitation_sum&forecast_days=7&timezone=Africa%2FOuagadougou`;
  try {
    const res = await fetchImpl(url, { signal: AbortSignal.timeout(6000) });
    if (!res.ok) throw new Error(String(res.status));
    const value = { available: true, ...assessRain((await res.json()).daily) };
    cache = { at: Date.now(), value };
    return value;
  } catch {
    return { available: false, rainy: false, message: 'Prévisions météo indisponibles' };
  }
}
