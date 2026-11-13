// Argent réel ou argent de test : une seule règle pour tout le serveur (décision du client, 13 novembre 2026).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Timestamp } from 'firebase-admin/firestore';
import { argentDeTestDe, dateDe, DEBUT_ARGENT_REEL_ORANGE, encaissementReel } from '../src/argent_reel';

const apres = Timestamp.fromDate(new Date(DEBUT_ARGENT_REEL_ORANGE.getTime() + 1));
const avant = Timestamp.fromDate(new Date(DEBUT_ARGENT_REEL_ORANGE.getTime() - 1));

test('argent réel : le vrai Wave, et Orange Money en production depuis le 2 novembre 2026 ; jamais le faux Wave ni le bac à sable', () => {
  assert.equal(encaissementReel('wave', avant.toDate()), true);
  assert.equal(encaissementReel('orange_money', apres.toDate()), true);
  assert.equal(encaissementReel('orange_money', avant.toDate()), false, 'bac à sable');
  assert.equal(encaissementReel('orange_money', null), false);
  for (const autre of ['simulation', 'portefeuille', undefined, null, '']) assert.equal(encaissementReel(autre, apres.toDate()), false, String(autre));
});

test('dateDe : seul un horodatage Firestore donne une date', () => {
  assert.equal(dateDe(apres)?.getTime(), apres.toMillis());
  for (const autre of [undefined, null, 'x', 12, new Date(), {}]) assert.equal(dateDe(autre), null);
});

test('argent de test : la marque posée à la création fait foi, vraie ou fausse', () => {
  assert.equal(argentDeTestDe({ argentDeTest: true, fournisseur: 'orange_money', creeLe: apres }), true);
  assert.equal(argentDeTestDe({ argentDeTest: false, fournisseur: 'simulation', creeLe: avant }), false);
});

test('argent de test : sans marque (paiement en cours à la mise en ligne), jugé sur le fournisseur et la date, jamais en argent réel par défaut', () => {
  assert.equal(argentDeTestDe({ fournisseur: 'simulation', creeLe: apres }), true, 'faux Wave');
  assert.equal(argentDeTestDe({ fournisseur: 'portefeuille', creeLe: apres }), true, 'solde : origine inconnue, prudence');
  assert.equal(argentDeTestDe({ fournisseur: 'orange_money', creeLe: avant }), true, 'bac à sable');
  assert.equal(argentDeTestDe({ fournisseur: 'orange_money', creeLe: apres }), false, 'Orange Money en production');
  assert.equal(argentDeTestDe({ fournisseur: 'wave', creeLe: apres }), false, 'vrai Wave');
  assert.equal(argentDeTestDe({}), true, 'document sans rien : jamais réel');
  // Une marque illisible n'en est pas une.
  for (const illisible of ['true', 1, null, {}]) {
    assert.equal(argentDeTestDe({ argentDeTest: illisible, fournisseur: 'simulation', creeLe: apres }), true, String(illisible));
    assert.equal(argentDeTestDe({ argentDeTest: illisible, fournisseur: 'orange_money', creeLe: apres }), false, String(illisible));
  }
});
