import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parseCsvLine, rowFilter } from '../../scripts/import-buildings.js';

test('lecture CSV avec guillemets', () => {
  assert.deepEqual(parseCsvLine('12.3,-1.5,"POLYGON((1,2),(3,4))",0.8'), ['12.3', '-1.5', 'POLYGON((1,2),(3,4))', '0.8']);
});

test('filtre emprise et confiance', () => {
  const keep = rowFilter({ bbox: [12.25, -1.7, 12.5, -1.35], minConfidence: 0.7 });
  assert.equal(keep(12.37, -1.52, 0.9), true);
  assert.equal(keep(12.37, -1.52, 0.5), false);
  assert.equal(keep(14, -1.52, 0.9), false);
  assert.equal(keep(12.37, -1.52, NaN), true);
});
