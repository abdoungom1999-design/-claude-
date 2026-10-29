import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { HttpsError } from 'firebase-functions/v2/https';
import { DISTANCE_MAX_KM, DISTANCE_TRAJET_MAX_KM, estimer, prixServeur, validerDemande } from '../src/commandes';
import type { CalculDistance } from '../src/distances';
import {
  ACCES_ORANGE_MONEY,
  METHODES_ACTIVES,
  METHODES_CONNUES,
  METHODES_RECHARGE,
  methodesPour,
  methodesRechargePour,
  verifierMethode,
  type Methode,
} from '../src/methodes_paiement';
import { COEFFICIENT_DETOUR, distanceRouteEstimeeKm, type Point } from '../src/tarification';

const PLATEAU = { latitude: 14.6928, longitude: -17.4467 };
const ALMADIES = { latitude: 14.7456, longitude: -17.5134 };
const KEUR_MASSAR = { latitude: 14.7836, longitude: -17.3114 };
const THIES = { latitude: 14.791, longitude: -16.9359 };
const GARE_DE_THIES = { latitude: 14.7892, longitude: -16.9253 };
const MBOUR = { latitude: 14.4196, longitude: -16.964 };
const SALY = { latitude: 14.4472, longitude: -17.0 };
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
    /dépasse 30 km/,
  );
  await rejete(estimer(compteur, 'awa', null, midi), 'invalid-argument');
  assert.equal(appels, 0);
});

test('commande : le prix envoyé ne sert que de contrôle, jamais de valeur', () => {
  assert.equal(validerDemande(commande()).prixAttendu, 2300);
  refuse(() => validerDemande(commande({ prixAttendu: 0 })), 'invalid-argument');
  refuse(() => validerDemande(commande({ prixAttendu: 2300.5 })), 'invalid-argument');
  refuse(() => validerDemande(commande({ prixAttendu: '2300' })), 'invalid-argument');
});

test('commande : 100 % mobile money (ou solde Sprint), adresses obligatoires', () => {
  refuse(() => validerDemande(commande({ methodePaiement: 'ESPECES' })), 'invalid-argument', /Wave ou votre solde Sprint/);
  assert.equal(validerDemande(commande({ methodePaiement: 'WAVE' })).methodePaiement, 'WAVE');
  assert.equal(validerDemande(commande({ methodePaiement: 'PORTEFEUILLE' })).methodePaiement, 'PORTEFEUILLE');
  refuse(() => validerDemande(commande({ adresseDepart: '  ' })), 'invalid-argument');
  refuse(() => validerDemande(commande({ adresseArrivee: 'x'.repeat(301) })), 'invalid-argument');
});

test('Orange Money : essai réservé aux testeurs (go du client, 29 octobre 2026), dans le serveur comme dans l\'app', () => {
  assert.equal(ACCES_ORANGE_MONEY, 'testeurs', 'ouverture à tous : seulement avec un nouveau go du client');
  // Jumeau dans l'app (choix du moyen de paiement), lu depuis functions/lib/test.
  const app = readFileSync(resolve(__dirname, '..', '..', '..', 'lib', 'core', 'widgets', 'payment_method_selector.dart'), 'utf8');
  const jumeau = app.match(/^const accesOrangeMoney = AccesOrangeMoney\.(ferme|testeurs|tous);$/m);
  assert.ok(jumeau, 'accesOrangeMoney introuvable dans payment_method_selector.dart : le texte a-t-il changé de forme ?');
  assert.equal(jumeau[1], ACCES_ORANGE_MONEY, 'l\'app proposerait un moyen que le serveur refuse (ou l\'inverse)');
  // La publication lit cette ligne telle quelle (secrets à vérifier, réponse attendue du webhook).
  const serveur = readFileSync(resolve(__dirname, '..', '..', 'src', 'methodes_paiement.ts'), 'utf8');
  assert.match(serveur, new RegExp(`^export const ACCES_ORANGE_MONEY: AccesOrangeMoney = '${ACCES_ORANGE_MONEY}';$`, 'm'));
});

test('accès à Orange Money : fermé pour tous, essai pour les seuls testeurs, puis ouvert à tous', () => {
  const avecOrange: Methode[] = ['WAVE', 'ORANGE_MONEY', 'PORTEFEUILLE'];
  const sansOrange: Methode[] = ['WAVE', 'PORTEFEUILLE'];
  assert.deepEqual(methodesPour(false, 'ferme'), sansOrange);
  assert.deepEqual(methodesPour(true, 'ferme'), sansOrange, 'fermé : même un testeur est refusé');
  assert.deepEqual(methodesPour(false, 'testeurs'), sansOrange, 'essai : invisible pour un client ordinaire');
  assert.deepEqual(methodesPour(true, 'testeurs'), avecOrange);
  assert.deepEqual(methodesPour(false, 'tous'), avecOrange);
  assert.deepEqual(methodesRechargePour(true, 'testeurs'), ['WAVE', 'ORANGE_MONEY']);
  assert.deepEqual(methodesRechargePour(false, 'testeurs'), ['WAVE']);
  // Réglage en service : un client ordinaire ne voit pas Orange Money.
  assert.deepEqual(METHODES_ACTIVES, methodesPour(false));
  assert.deepEqual(METHODES_RECHARGE, methodesRechargePour(false));
});

test('commande : Orange Money fermé tant que le client n\'a pas donné son go', () => {
  // Précondition non remplie (et non « argument invalide ») : le message dit quoi choisir.
  refuse(
    () => validerDemande(commande({ methodePaiement: 'ORANGE_MONEY' })),
    'failed-precondition',
    /Orange Money n'est pas encore disponible : payez avec Wave ou votre solde Sprint/,
  );
  // Connu (l'historique en contient) mais jamais accepté pour un nouveau paiement.
  assert.ok(METHODES_CONNUES.includes('ORANGE_MONEY'));
  assert.ok(!METHODES_ACTIVES.includes('ORANGE_MONEY'));
  assert.ok(!METHODES_RECHARGE.includes('ORANGE_MONEY'));
  // Toute autre valeur n'est pas un moyen de paiement.
  for (const valeur of ['orange_money', 'Orange Money', 'ORANGE_MONEY ', '', null, undefined, 7, ['ORANGE_MONEY']]) {
    refuse(() => validerDemande(commande({ methodePaiement: valeur })), 'invalid-argument');
  }
});

test('Orange Money ouvert (essais) : accepté pour une course comme pour une recharge, le solde jamais pour recharger', () => {
  const ouvertes: Methode[] = ['WAVE', 'ORANGE_MONEY', 'PORTEFEUILLE'];
  assert.equal(validerDemande(commande({ methodePaiement: 'ORANGE_MONEY' }), ouvertes).methodePaiement, 'ORANGE_MONEY');
  assert.equal(validerDemande(commande({ methodePaiement: 'WAVE' }), ouvertes).methodePaiement, 'WAVE');
  assert.equal(verifierMethode('ORANGE_MONEY', ['WAVE', 'ORANGE_MONEY'], 'recharger'), 'ORANGE_MONEY');
  refuse(() => verifierMethode('PORTEFEUILLE', ['WAVE', 'ORANGE_MONEY'], 'recharger'), 'invalid-argument', /Wave ou Orange Money/);
});

test('recharge : le mobile money actif est Wave seul', () => {
  assert.deepEqual([...METHODES_RECHARGE], ['WAVE']);
  assert.equal(verifierMethode('WAVE', METHODES_RECHARGE, 'recharger'), 'WAVE');
  refuse(() => verifierMethode('ORANGE_MONEY', METHODES_RECHARGE, 'recharger'), 'failed-precondition', /rechargez avec Wave\./);
  refuse(() => verifierMethode('PORTEFEUILLE', METHODES_RECHARGE, 'recharger'), 'invalid-argument', /Wave uniquement/);
});

// --- Sprint = petits trajets à l'intérieur d'une même ville (décision du client, 12 octobre 2026) ---

test('trajet entre deux villes (Dakar → Thiès...) : refusé, message clair, sans appeler Google, pour l\'estimation comme pour le paiement', async () => {
  let appels = 0;
  const compteur: CalculDistance = async (d, a) => {
    appels++;
    return route13(d, a);
  };
  const entreVilles: [string, Point, Point][] = [
    ['Dakar → Thiès', PLATEAU, THIES],
    ['Thiès → Dakar', THIES, PLATEAU],
    ['Thiès → Mbour', THIES, MBOUR],
    ['Mbour → Dakar', MBOUR, PLATEAU],
  ];
  for (const [nom, depart, arrivee] of entreVilles) {
    for (const type of ['PASSAGER', 'COLIS']) {
      await rejete(estimer(compteur, 'awa', { type, depart, arrivee }, midi), 'invalid-argument', /dépasse 30 km.*même ville.*Dakar, Thiès ou Mbour/);
    }
    refuse(() => validerDemande(commande({ depart, arrivee })), 'invalid-argument', /dépasse 30 km/);
    refuse(() => validerDemande(commande({ depart, arrivee, methodePaiement: 'PORTEFEUILLE' })), 'invalid-argument', /dépasse 30 km/);
    assert.ok(distanceRouteEstimeeKm(depart, arrivee) > DISTANCE_TRAJET_MAX_KM, nom);
  }
  assert.equal(appels, 0);
});

test('petits trajets dans une même ville : acceptés (Dakar de bout en bout, Thiès, Mbour et Saly)', async () => {
  const petits: [string, Point, Point][] = [
    ['Plateau → Almadies', PLATEAU, ALMADIES],
    ['Keur Massar → Almadies (le plus long de Dakar)', KEUR_MASSAR, ALMADIES],
    ['Thiès centre → gare', THIES, GARE_DE_THIES],
    ['Mbour → Saly', MBOUR, SALY],
  ];
  for (const [nom, depart, arrivee] of petits) {
    assert.ok(distanceRouteEstimeeKm(depart, arrivee) <= DISTANCE_TRAJET_MAX_KM, nom);
    const e = await estimer(route13, 'awa', { type: 'PASSAGER', depart, arrivee }, midi);
    assert.ok(e.prixFcfa > 0, nom);
    assert.equal(validerDemande(commande({ depart, arrivee })).distanceKm, distanceRouteEstimeeKm(depart, arrivee), nom);
  }
});

test('plafond du trajet : 30 km mesurés en vol d\'oiseau x 1,1 (29,9 passe, 30,1 non) ; 100 km restent la protection contre les saisies absurdes', async () => {
  assert.equal(DISTANCE_TRAJET_MAX_KM, 30);
  assert.equal(DISTANCE_MAX_KM, 100);
  const arrivee = (km: number): Point => ({ latitude: PLATEAU.latitude + km / COEFFICIENT_DETOUR / 111.195, longitude: PLATEAU.longitude });
  assert.ok(Math.abs(distanceRouteEstimeeKm(PLATEAU, arrivee(29.9)) - 29.9) < 0.01);

  const e = await estimer(route13, 'awa', { type: 'PASSAGER', depart: PLATEAU, arrivee: arrivee(29.9) }, midi);
  assert.ok(e.prixFcfa > 0);
  await rejete(estimer(route13, 'awa', { type: 'PASSAGER', depart: PLATEAU, arrivee: arrivee(30.1) }, midi), 'invalid-argument', /dépasse 30 km/);
});

test('zone tarifaire : Thiès et Mbour = province, Dakar et sa banlieue = Dakar, pour l\'estimation comme pour le prix recalculé à la commande', async () => {
  const cas: [string, Point, Point, string][] = [
    ['Plateau', PLATEAU, ALMADIES, 'DAKAR'],
    ['Keur Massar', KEUR_MASSAR, PLATEAU, 'DAKAR'],
    ['Thiès', THIES, GARE_DE_THIES, 'PROVINCE'],
    ['Mbour', MBOUR, SALY, 'PROVINCE'],
    ['Saly', SALY, MBOUR, 'PROVINCE'],
  ];
  for (const [nom, depart, arrivee, zone] of cas) {
    const estimation = await estimer(route13, 'awa', { type: 'PASSAGER', depart, arrivee }, midi);
    assert.equal(estimation.zoneTarifaire, zone, nom);
    // À la commande, le serveur recalcule avec la même grille : le prix vu est le prix payé.
    const recalcule = await prixServeur(route13, validerDemande(commande({ depart, arrivee, prixAttendu: estimation.prixFcfa })), midi);
    assert.equal(recalcule.estimation.zoneTarifaire, zone, nom);
    assert.equal(recalcule.estimation.prixFcfa, estimation.prixFcfa, nom);
  }
});
