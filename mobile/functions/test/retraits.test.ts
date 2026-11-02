// Retraits du solde Sprint (lot B) : réglages et numéro de réception.
// Le parcours complet (solde, livre, Admin) est dans retraits.emulateur.test.ts.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { MOYENS_RETRAIT, numeroSenegal, RETRAIT_MIN_FCFA, RETRAITS_OUVERTS } from '../src/retraits';

/** Jumeau dans l'app, lu depuis functions/lib/test. */
const app = () => readFileSync(resolve(__dirname, '..', '..', '..', 'lib', 'features', 'portefeuille', 'data', 'retraits.dart'), 'utf8');

test('retraits : fermés tant que le client n\'a pas donné son go, dans le serveur comme dans l\'app', () => {
  assert.equal(RETRAITS_OUVERTS, false, 'ouverture des retraits : seulement avec le go du client');
  const jumeau = app().match(/^const retraitsOuverts = (true|false);$/m);
  assert.ok(jumeau, 'retraitsOuverts introuvable dans retraits.dart : le texte a-t-il changé de forme ?');
  assert.equal(jumeau[1], String(RETRAITS_OUVERTS), 'l\'app proposerait un retrait que le serveur refuse (ou l\'inverse)');
  // Ligne lue telle quelle : le réglage ne se cache pas derrière un calcul.
  const serveur = readFileSync(resolve(__dirname, '..', '..', 'src', 'retraits.ts'), 'utf8');
  assert.match(serveur, new RegExp(`^export const RETRAITS_OUVERTS: boolean = ${RETRAITS_OUVERTS};$`, 'm'));
});

test('retraits : même minimum et mêmes moyens dans le serveur et dans l\'app', () => {
  const texte = app();
  const minimum = texte.match(/^const retraitMinFcfa = (\d+);$/m);
  assert.ok(minimum, 'retraitMinFcfa introuvable dans retraits.dart');
  assert.equal(Number(minimum[1]), RETRAIT_MIN_FCFA);
  const moyens = [...texte.matchAll(/^ {2}\w+\('([A-Z_]+)', '[^']+'\)[,;]$/gm)].map((m) => m[1]);
  assert.deepEqual(moyens, [...MOYENS_RETRAIT]);
});

// Mêmes cas que test/retraits_test.dart (règle écrite deux fois : serveur et app).
const NUMEROS_VALIDES: ReadonlyArray<[string, string]> = [
  ['771234567', '771234567'],
  ['77 123 45 67', '771234567'],
  ['77.123.45.67', '771234567'],
  ['77-123-45-67', '771234567'],
  ['+221 77 123 45 67', '771234567'],
  ['+221771234567', '771234567'],
  ['00221 76 123 45 67', '761234567'],
  ['221781234567', '781234567'],
  ['70 123 45 67', '701234567'],
  ['75 123 45 67', '751234567'],
];
const NUMEROS_INVALIDES = [
  '',
  '   ',
  '77123456',
  '7712345678',
  '33 823 45 67',
  '+221 33 823 45 67',
  '72 123 45 67',
  '79 123 45 67',
  '+33 6 12 34 56 78',
  '0033612345678',
  '221 33 823 45 67',
  '77 123 45 6a',
  '+22177123456',
  '77_123_45_67',
];

test('numéro de réception : mobile sénégalais (70, 75, 76, 77, 78), indicatif et séparateurs acceptés', () => {
  for (const [saisi, attendu] of NUMEROS_VALIDES) assert.equal(numeroSenegal(saisi), attendu, saisi);
  for (const saisi of NUMEROS_INVALIDES) assert.equal(numeroSenegal(saisi), null, saisi);
  for (const autre of [undefined, null, 771234567, ['771234567'], { numero: '771234567' }]) {
    assert.equal(numeroSenegal(autre), null, JSON.stringify(autre));
  }
});
