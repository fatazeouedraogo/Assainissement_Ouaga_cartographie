import assert from 'node:assert/strict';
import { test } from 'node:test';
import { combineConfidence, dumpStatusFor, evaluateReport, hammingHex, hexToBits, inOuaga, medianSize, trustOf } from '../../src/services/rules.js';

const base = { lat: 12.37, lon: -1.52, accuracyM: 12, photo: { present: true, analysis: { valid_image: true, flags: [] } }, sameUserNearby: false, photoMatches: [], trust: 0.5 };

test('zone de Ouagadougou', () => {
  assert.equal(inOuaga(12.37, -1.52), true);
  assert.equal(inOuaga(14.0, -1.52), false);
});

test('signalement valide accepté', () => {
  const r = evaluateReport(base);
  assert.equal(r.decision, 'accept');
  assert.ok(r.credibility > 0.7);
});

test('rejets : hors zone, sans photo, doublon, photo réutilisée', () => {
  assert.deepEqual(evaluateReport({ ...base, lat: 14 }).rejectReasons, ['hors_zone']);
  assert.ok(evaluateReport({ ...base, photo: { present: false } }).rejectReasons.includes('photo_absente'));
  assert.ok(evaluateReport({ ...base, sameUserNearby: true }).rejectReasons.includes('doublon_meme_auteur'));
  assert.ok(evaluateReport({ ...base, photoMatches: [{ distanceM: 900, sameUser: false }] }).rejectReasons.includes('photo_reutilisee'));
});

test('signalements douteux marqués sans rejet', () => {
  const r = evaluateReport({ ...base, accuracyM: 150, photoMatches: [{ distanceM: 20, sameUser: false }] });
  assert.equal(r.decision, 'flag');
  assert.ok(r.flags.includes('gps_imprecis') && r.flags.includes('photo_copie_suspecte'));
  assert.ok(r.credibility < evaluateReport(base).credibility);
});

test('déplacement impossible détecté', () => {
  const r = evaluateReport({ ...base, lastReport: { distanceM: 30000, seconds: 300 } });
  assert.ok(r.flags.includes('deplacement_impossible'));
});

test('confiance par recoupement (noisy-OR)', () => {
  assert.ok(Math.abs(combineConfidence([0.5, 0.5]) - 0.75) < 1e-9);
  assert.ok(combineConfidence([0.8, 0.8, 0.8]) > 0.99);
  assert.equal(combineConfidence([]), 0);
});

test('statut automatique du dépotoir', () => {
  const thresholds = { auto_verify_confidence: 0.9, auto_verify_reporters: 3 };
  assert.equal(dumpStatusFor({ confidence: 0.95, reporters: 3, current: 'pending', thresholds }), 'verified');
  assert.equal(dumpStatusFor({ confidence: 0.95, reporters: 2, current: 'pending', thresholds }), 'pending');
  assert.equal(dumpStatusFor({ confidence: 0.99, reporters: 5, current: 'cleaned', thresholds }), 'cleaned');
});

test('distance de Hamming et conversion binaire', () => {
  assert.equal(hammingHex('0000000000000000', 'ffffffffffffffff'), 64);
  assert.equal(hammingHex('15c890924260819a', '15c890924260819b'), 1);
  assert.equal(hexToBits('00000000000000ff').length, 64);
});

test('médiane des tailles et confiance de l’auteur', () => {
  assert.equal(medianSize(['small', 'large', 'large']), 'large');
  assert.equal(medianSize([]), 'medium');
  assert.ok(trustOf(10, 0) > trustOf(0, 5));
});
