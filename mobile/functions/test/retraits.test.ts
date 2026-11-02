// Retraits du solde Sprint (lot B) : réglages et numéro de réception.
// Le parcours complet (solde, livre, Admin) est dans retraits.emulateur.test.ts.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  DEBUT_ARGENT_REEL_ORANGE,
  DELAI_VERSEMENT_HEURES,
  encaissementReel,
  fraisMaxFcfa,
  jourDakar,
  MOYENS_RETRAIT,
  numeroSenegal,
  RETRAIT_MAX_JOUR_FCFA,
  RETRAIT_MIN_FCFA,
  RETRAITS_OUVERTS,
} from '../src/retraits';

/** Jumeau dans l'app, lu depuis functions/lib/test. */
const app = () => readFileSync(resolve(__dirname, '..', '..', '..', 'lib', 'features', 'portefeuille', 'data', 'retraits.dart'), 'utf8');

test('retraits : ouverts (go du client, 2 novembre 2026), dans le serveur comme dans l\'app', () => {
  assert.equal(RETRAITS_OUVERTS, true, 'fermeture des retraits : seulement avec un nouveau go du client');
  const jumeau = app().match(/^const retraitsOuverts = (true|false);$/m);
  assert.ok(jumeau, 'retraitsOuverts introuvable dans retraits.dart : le texte a-t-il changé de forme ?');
  assert.equal(jumeau[1], String(RETRAITS_OUVERTS), 'l\'app proposerait un retrait que le serveur refuse (ou l\'inverse)');
  // Ligne lue telle quelle : le réglage ne se cache pas derrière un calcul.
  const serveur = readFileSync(resolve(__dirname, '..', '..', 'src', 'retraits.ts'), 'utf8');
  assert.match(serveur, new RegExp(`^export const RETRAITS_OUVERTS: boolean = ${RETRAITS_OUVERTS};$`, 'm'));
});

test('retraits : décisions du client (2 novembre 2026) : 500 FCFA au moins, 50 000 FCFA par jour, envoi sous 48 h', () => {
  assert.equal(RETRAIT_MIN_FCFA, 500);
  assert.equal(RETRAIT_MAX_JOUR_FCFA, 50_000);
  assert.equal(DELAI_VERSEMENT_HEURES, 48);
});

test('retraits : mêmes minimum, plafond, délai et moyens dans le serveur et dans l\'app', () => {
  const texte = app();
  const nombre = (nom: string) => {
    const valeur = texte.match(new RegExp(`^const ${nom} = (\\d+);$`, 'm'));
    assert.ok(valeur, `${nom} introuvable dans retraits.dart`);
    return Number(valeur[1]);
  };
  assert.equal(nombre('retraitMinFcfa'), RETRAIT_MIN_FCFA);
  assert.equal(nombre('retraitMaxJourFcfa'), RETRAIT_MAX_JOUR_FCFA);
  assert.equal(nombre('delaiVersementHeures'), DELAI_VERSEMENT_HEURES);
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

test('argent réel : vrai Wave, ou Orange Money en production (depuis la publication 114) ; jamais le faux Wave ni le bac à sable', () => {
  const apres = new Date(DEBUT_ARGENT_REEL_ORANGE.getTime() + 1);
  const avant = new Date(DEBUT_ARGENT_REEL_ORANGE.getTime() - 1);
  assert.equal(encaissementReel('orange_money', apres), true);
  assert.equal(encaissementReel('orange_money', DEBUT_ARGENT_REEL_ORANGE), true);
  assert.equal(encaissementReel('orange_money', avant), false, 'bac à sable');
  assert.equal(encaissementReel('orange_money', null), false);
  assert.equal(encaissementReel('wave', avant), true, 'vrai Wave (pas encore branché)');
  for (const autre of ['simulation', 'portefeuille', undefined, '']) assert.equal(encaissementReel(autre, apres), false, String(autre));
});

test('plafond du jour : de minuit à minuit à Dakar (UTC toute l\'année)', () => {
  assert.equal(jourDakar(new Date('2026-11-02T00:00:00Z')), '2026-11-02');
  assert.equal(jourDakar(new Date('2026-11-02T23:59:59Z')), '2026-11-02');
  assert.equal(jourDakar(new Date('2026-11-03T00:00:00Z')), '2026-11-03');
});

test('frais de transfert au versement : au plus 10 % (100 FCFA au moins), toujours moins que le montant', () => {
  assert.equal(fraisMaxFcfa(500), 100);
  assert.equal(fraisMaxFcfa(1000), 100);
  assert.equal(fraisMaxFcfa(5000), 500);
  assert.equal(fraisMaxFcfa(50000), 5000);
  assert.equal(fraisMaxFcfa(100), 99);
});
