import assert from 'node:assert/strict';
import { test } from 'node:test';
import { assessRain } from '../../src/services/weather.js';

test('pluie forte : trois jours à 10 mm', () => {
  const r = assessRain({ time: ['a', 'b', 'c', 'd', 'e', 'f', 'g'], precipitation_sum: [12, 15, 0, 11, 1, 0, 0] });
  assert.equal(r.rainy, true);
  assert.equal(r.wet_days, 3);
});

test('pluie forte : un jour à 45 mm', () => {
  assert.equal(assessRain({ time: ['a'], precipitation_sum: [45] }).rainy, true);
});

test('temps sec ou faibles averses', () => {
  const r = assessRain({ time: ['a', 'b', 'c'], precipitation_sum: [0, 4, 9] });
  assert.equal(r.rainy, false);
  assert.equal(r.total_mm, 13);
});
