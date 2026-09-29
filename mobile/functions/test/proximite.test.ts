// Anonymisation des chauffeurs à proximité (sans émulateur) : npm test.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { arrondirCap, arrondirPosition, distanceKm, PAS_ANONYMISATION_M } from '../src/proximite';

test('position ramenée au centre de sa case : écart d\'au plus ~106 m (demi-diagonale de 150 m)', () => {
  for (let i = 0; i < 500; i++) {
    const lat = 14.65 + Math.random() * 0.1;
    const lng = -17.5 + Math.random() * 0.1;
    const a = arrondirPosition(lat, lng);
    const ecartM = distanceKm(lat, lng, a.latitude, a.longitude) * 1000;
    assert.ok(ecartM <= (PAS_ANONYMISATION_M * Math.SQRT2) / 2 + 2, `écart ${ecartM} m`);
  }
});

test('deux chauffeurs proches dans la même case : même position renvoyée', () => {
  const a = arrondirPosition(14.69280, -17.44670);
  const b = arrondirPosition(14.69285, -17.44665); // ~7 m plus loin
  assert.deepEqual(a, b);
});

test('position arrondie à 5 décimales, jamais la valeur exacte', () => {
  const exacte = { latitude: 14.692812345, longitude: -17.446712345 };
  const a = arrondirPosition(exacte.latitude, exacte.longitude);
  assert.notEqual(a.latitude, exacte.latitude);
  assert.equal(a.latitude, Math.round(a.latitude * 1e5) / 1e5);
});

test('cap arrondi à 45° (8 directions), inconnu si absent ou négatif', () => {
  assert.equal(arrondirCap(0), 0);
  assert.equal(arrondirCap(30), 45);
  assert.equal(arrondirCap(350), 0);
  assert.equal(arrondirCap(181), 180);
  assert.equal(arrondirCap(-1), null);
  assert.equal(arrondirCap(null), null);
  assert.equal(arrondirCap('90'), null);
});
