import { test } from 'node:test';
import assert from 'node:assert/strict';
import { HttpsError } from 'firebase-functions/v2/https';
import { estimer, idCourse, validerCommande } from '../src/commandes';

const PLATEAU = { latitude: 14.6928, longitude: -17.4467 };
const ALMADIES = { latitude: 14.7456, longitude: -17.5134 };
const midi = new Date(Date.UTC(2026, 8, 27, 12));

const commande = (extra: Record<string, unknown> = {}) => ({
  type: 'PASSAGER',
  depart: PLATEAU,
  arrivee: ALMADIES,
  adresseDepart: 'Plateau',
  adresseArrivee: 'Almadies',
  methodePaiement: 'WAVE',
  transactionId: 'TXN-WAVE-DEMO-1',
  prixAttendu: 2300,
  ...extra,
});

function refuse(fn: () => unknown, code: string, message?: RegExp) {
  assert.throws(fn, (e: unknown) => {
    assert.ok(e instanceof HttpsError);
    assert.equal(e.code, code);
    if (message) assert.match(e.message, message);
    return true;
  });
}

test('estimation : prix et distance calculés par le serveur depuis les coordonnées', () => {
  const e = estimer('awa', { type: 'PASSAGER', depart: PLATEAU, arrivee: ALMADIES }, midi);
  assert.equal(e.prixFcfa, 2300);
  assert.ok(e.distanceKm > 10 && e.distanceKm < 10.3);
});

test('estimation : connexion obligatoire', () => {
  refuse(() => estimer(undefined, { type: 'PASSAGER', depart: PLATEAU, arrivee: ALMADIES }, midi), 'unauthenticated');
});

test('trajet invalide : type, coordonnées, même lieu, hors zone', () => {
  refuse(() => estimer('awa', { type: 'TAXI', depart: PLATEAU, arrivee: ALMADIES }, midi), 'invalid-argument');
  refuse(() => estimer('awa', { type: 'PASSAGER', depart: { latitude: '14.7', longitude: -17 }, arrivee: ALMADIES }, midi), 'invalid-argument');
  refuse(() => estimer('awa', { type: 'PASSAGER', depart: { latitude: 95, longitude: -17 }, arrivee: ALMADIES }, midi), 'invalid-argument');
  refuse(() => estimer('awa', { type: 'PASSAGER', depart: PLATEAU, arrivee: PLATEAU }, midi), 'invalid-argument', /identiques/);
  refuse(
    () => estimer('awa', { type: 'PASSAGER', depart: PLATEAU, arrivee: { latitude: 16.02, longitude: -16.5 } }, midi),
    'invalid-argument',
    /hors de la zone/,
  );
  refuse(() => estimer('awa', null, midi), 'invalid-argument');
});

test('commande : le prix envoyé ne sert que de contrôle, jamais de valeur', () => {
  assert.equal(validerCommande(commande()).prixAttendu, 2300);
  refuse(() => validerCommande(commande({ prixAttendu: 0 })), 'invalid-argument');
  refuse(() => validerCommande(commande({ prixAttendu: 2300.5 })), 'invalid-argument');
  refuse(() => validerCommande(commande({ prixAttendu: '2300' })), 'invalid-argument');
});

test('commande : 100 % mobile money, adresses et identifiant de paiement obligatoires', () => {
  refuse(() => validerCommande(commande({ methodePaiement: 'ESPECES' })), 'invalid-argument', /Wave ou Orange Money/);
  refuse(() => validerCommande(commande({ adresseDepart: '  ' })), 'invalid-argument');
  refuse(() => validerCommande(commande({ adresseArrivee: 'x'.repeat(301) })), 'invalid-argument');
  refuse(() => validerCommande(commande({ transactionId: undefined })), 'invalid-argument');
});

test('identifiant de course stable pour une même transaction, distinct sinon', () => {
  assert.equal(idCourse('awa', 'TXN-1'), idCourse('awa', 'TXN-1'));
  assert.notEqual(idCourse('awa', 'TXN-1'), idCourse('awa', 'TXN-2'));
  assert.notEqual(idCourse('awa', 'TXN-1'), idCourse('fatou', 'TXN-1'));
});
