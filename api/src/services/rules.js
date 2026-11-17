import { OUAGA_BBOX } from '../config.js';

export const SIZE_KG = { small: 50, medium: 300, large: 1500 };
export const DUP_RADIUS_M = 30;
export const PHOTO_COPY_HAMMING = 4;

export const inOuaga = (lat, lon) =>
  lat >= OUAGA_BBOX.south && lat <= OUAGA_BBOX.north && lon >= OUAGA_BBOX.west && lon <= OUAGA_BBOX.east;

export function hexToBits(hex) {
  return BigInt(`0x${hex}`).toString(2).padStart(64, '0');
}

export function hammingHex(a, b) {
  let x = BigInt(`0x${a}`) ^ BigInt(`0x${b}`);
  let n = 0;
  while (x > 0n) {
    n += Number(x & 1n);
    x >>= 1n;
  }
  return n;
}

export function combineConfidence(credibilities) {
  return 1 - credibilities.reduce((acc, c) => acc * (1 - Math.min(Math.max(c, 0), 0.99)), 1);
}

export function medianSize(sizes) {
  const order = ['small', 'medium', 'large'];
  const sorted = sizes.map((s) => order.indexOf(s)).filter((i) => i >= 0).sort((a, b) => a - b);
  if (!sorted.length) return 'medium';
  return order[sorted[Math.floor(sorted.length / 2)]];
}

export function trustOf(verified, rejected) {
  return (verified + 1) / (verified + rejected + 2);
}

export function evaluateReport(input) {
  const { lat, lon, accuracyM, photo, sameUserNearby, photoMatches = [], trust = 0.5, lastReport = null } = input;
  const reject = [];
  const flags = [];

  if (!inOuaga(lat, lon)) reject.push('hors_zone');
  if (!photo?.present) reject.push('photo_absente');
  if (photo?.analysis && photo.analysis.valid_image === false) reject.push('photo_illisible');
  if (sameUserNearby) reject.push('doublon_meme_auteur');
  if (photoMatches.some((m) => m.distanceM > 100 || m.sameUser)) reject.push('photo_reutilisee');

  const analysisFlags = photo?.analysis?.flags || [];
  if (analysisFlags.includes('too_blurry')) flags.push('photo_floue');
  if (analysisFlags.includes('too_dark')) flags.push('photo_sombre');
  if (analysisFlags.includes('not_a_dump')) flags.push('contenu_douteux');
  if (photoMatches.some((m) => m.distanceM <= 100 && !m.sameUser)) flags.push('photo_copie_suspecte');
  if (accuracyM != null && accuracyM > 80) flags.push('gps_imprecis');
  if (lastReport && lastReport.seconds > 0) {
    const speed = lastReport.distanceM / lastReport.seconds;
    if (lastReport.distanceM > 2000 && speed > 40) flags.push('deplacement_impossible');
  }
  if (!photo?.analysis) flags.push('analyse_indisponible');

  let c = 0.35;
  if (photo?.present && !flags.includes('photo_floue') && !flags.includes('photo_sombre')) c += 0.2;
  if (accuracyM != null) c += accuracyM <= 30 ? 0.15 : accuracyM <= 80 ? 0.05 : 0;
  c += 0.25 * trust;
  for (const f of ['contenu_douteux', 'photo_copie_suspecte', 'deplacement_impossible']) if (flags.includes(f)) c -= 0.2;
  if (flags.includes('gps_imprecis')) c -= 0.1;
  c = Math.min(0.95, Math.max(0.05, c));

  return {
    decision: reject.length ? 'reject' : flags.length ? 'flag' : 'accept',
    rejectReasons: reject,
    flags,
    credibility: Number(c.toFixed(3)),
  };
}

export function dumpStatusFor({ confidence, reporters, current, thresholds }) {
  if (current !== 'pending') return current;
  return confidence >= thresholds.auto_verify_confidence && reporters >= thresholds.auto_verify_reporters ? 'verified' : 'pending';
}
