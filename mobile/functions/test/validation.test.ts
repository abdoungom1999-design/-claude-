import { test } from 'node:test';
import assert from 'node:assert/strict';
import { HttpsError } from 'firebase-functions/v2/https';
import { estimer, idCourse, validerCommande } from '../src/commandes';
import type { CalculDistance } from '../src/distances';
import { distanceRouteEstimeeKm } from '../src/tarification';

const PLATEAU = { latitude: 14.6928, longitude: -17.4467 };
const ALMADIES = { latitude: 14.7456, longitude: -17.5134 };
const midi = new Date(Date.UTC(2026, 8, 27, 12));

/** Secours sans Google : vol d'oiseau x 1,1. */
const volOiseau: CalculDistance = async (d, a) => ({ distanceKm: distanceRouteEstimeeKm(d, a), source: 'estimation' });
/** Distance par la route simulée : 13 km. */
const route13: CalculDistance = async () => ({ distanceKm: 13, source: 'route' });

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

test('estimation : prix calculé par le serveur sur la distance par la route', async () => {
  const e = await estimer(route13, 'awa', { type: 'PASSAGER', depart: PLATEAU, arrivee: ALMADIES }, midi);
  assert.equal(e.distanceKm, 13);
  assert.equal(e.prixFcfa, 2900); // 300 + 13 x 200
  assert.equal(e.sourceDistance, 'route');
});

test('estimation : sans Google, secours sur le vol d\'oiseau x 1,1', async () => {
  const e = await estimer(volOiseau, 'awa', { type: 'PASSAGER', depart: PLATEAU, arrivee: ALMADIES }, midi);
  assert.equal(e.prixFcfa, 2300);
  assert.equal(e.sourceDistance, 'estimation');
  assert.ok(e.distanceKm > 10 && e.distanceKm < 10.3);
});

async function rejete(promesse: Promise<unknown>, code: string, message?: RegExp) {
  await assert.rejects(promesse, (e: unknown) => {
    assert.ok(e instanceof HttpsError);
    assert.equal(e.code, code);
    if (message) assert.match(e.message, message);
    return true;
  });
}

test('estimation : connexion obligatoire', async () => {
  await rejete(estimer(route13, undefined, { type: 'PASSAGER', depart: PLATEAU, arrivee: ALMADIES }, midi), 'unauthenticated');
});

test('trajet invalide : type, coordonnées, même lieu, hors zone (sans appeler Google)', async () => {
  let appels = 0;
  const compteur: CalculDistance = async (d, a) => {
    appels++;
    return route13(d, a);
  };
  await rejete(estimer(compteur, 'awa', { type: 'TAXI', depart: PLATEAU, arrivee: ALMADIES }, midi), 'invalid-argument');
  await rejete(estimer(compteur, 'awa', { type: 'PASSAGER', depart: { latitude: '14.7', longitude: -17 }, arrivee: ALMADIES }, midi), 'invalid-argument');
  await rejete(estimer(compteur, 'awa', { type: 'PASSAGER', depart: { latitude: 95, longitude: -17 }, arrivee: ALMADIES }, midi), 'invalid-argument');
  await rejete(estimer(compteur, 'awa', { type: 'PASSAGER', depart: PLATEAU, arrivee: PLATEAU }, midi), 'invalid-argument', /identiques/);
  await rejete(
    estimer(compteur, 'awa', { type: 'PASSAGER', depart: PLATEAU, arrivee: { latitude: 16.02, longitude: -16.5 } }, midi),
    'invalid-argument',
    /hors de la zone/,
  );
  await rejete(estimer(compteur, 'awa', null, midi), 'invalid-argument');
  assert.equal(appels, 0);
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
