// Observation (phase C de la sécurité) : fréquence des appels et e-mail non
// vérifié. Le principe testé partout : on REGARDE et on le dit, jamais d'erreur
// ni de refus.
import { afterEach, beforeEach, mock, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { logger } from 'firebase-functions';
import {
  type ActiviteAnormale,
  MULTIPLE_ALERTE_ADMIN,
  ObservateurFrequence,
  observerEmail,
  REGLES_FREQUENCE,
  sansRetarder,
} from '../src/observation';

type Ligne = [string, Record<string, unknown> | undefined];
let avertissements: Ligne[];
let informations: Ligne[];
let erreurs: Ligne[];

beforeEach(() => {
  avertissements = [];
  informations = [];
  erreurs = [];
  mock.method(logger, 'warn', (texte: string, donnees?: Record<string, unknown>) => avertissements.push([texte, donnees]));
  mock.method(logger, 'info', (texte: string, donnees?: Record<string, unknown>) => informations.push([texte, donnees]));
  mock.method(logger, 'error', (texte: string, donnees?: Record<string, unknown>) => erreurs.push([texte, donnees]));
});
afterEach(() => mock.restoreAll());

const SEUIL = REGLES_FREQUENCE.creerPaiement.seuil;
const FENETRE_MS = REGLES_FREQUENCE.creerPaiement.fenetreSecondes * 1000;

/** Observateur à horloge réglable, qui note les alertes aux Admin. */
function observateur(alerter?: (a: ActiviteAnormale) => Promise<void>) {
  const horloge = { t: Date.UTC(2026, 10, 13, 12) };
  const alertes: ActiviteAnormale[] = [];
  const obs = new ObservateurFrequence(
    alerter ?? (async (a) => void alertes.push(a)),
    () => horloge.t,
  );
  return { obs, horloge, alertes };
}

test('sous le seuil : rien n\'est signalé', async () => {
  const { obs } = observateur();
  for (let i = 0; i < SEUIL; i++) assert.equal(await obs.observer('creerPaiement', 'awa'), false);
  assert.equal(avertissements.length, 0);
});

test('au-delà du seuil : signalé une seule fois par fenêtre, et rien n\'est jamais refusé (aucune erreur levée)', async () => {
  const { obs, horloge } = observateur();
  for (let i = 0; i < SEUIL; i++) await obs.observer('creerPaiement', 'awa');
  for (let i = 0; i < 10; i++) assert.equal(await obs.observer('creerPaiement', 'awa'), true);
  assert.equal(avertissements.length, 1);
  assert.match(avertissements[0][0], /fréquence anormale \(rien n'est refusé\)/);
  assert.equal(avertissements[0][1]?.uid, 'awa');
  assert.equal(avertissements[0][1]?.fonction, 'creerPaiement');
  assert.equal(avertissements[0][1]?.seuil, SEUIL);

  // Une minute plus tard, le même abus est signalé de nouveau.
  horloge.t += FENETRE_MS + 1;
  for (let i = 0; i <= SEUIL; i++) await obs.observer('creerPaiement', 'awa');
  assert.equal(avertissements.length, 2);
});

test('chaque compte et chaque fonction ont leur propre compte', async () => {
  const { obs } = observateur();
  for (let i = 0; i <= SEUIL; i++) await obs.observer('creerPaiement', 'awa');
  assert.equal(await obs.observer('creerPaiement', 'fatou'), false, 'un autre compte n\'est pas touché');
  assert.equal(await obs.observer('creerRecharge', 'awa'), false, 'une autre fonction non plus');
});

test('fenêtre glissante : les appels de plus d\'une minute ne comptent plus', async () => {
  const { obs, horloge } = observateur();
  for (let i = 0; i < SEUIL; i++) await obs.observer('creerPaiement', 'awa');
  horloge.t += FENETRE_MS - 1;
  assert.equal(await obs.observer('creerPaiement', 'awa'), true, 'juste dans la fenêtre : le septième appel dépasse');
  horloge.t += FENETRE_MS;
  assert.equal(await obs.observer('creerPaiement', 'awa'), false, 'passé la fenêtre : on repart de zéro');
});

test('fonction non surveillée, compte inconnu : ignoré sans bruit', async () => {
  const { obs } = observateur();
  for (let i = 0; i < 500; i++) {
    assert.equal(await obs.observer('fonctionInconnue', 'awa'), false);
    assert.equal(await obs.observer('creerPaiement', undefined), false);
  }
  assert.equal(avertissements.length + erreurs.length, 0);
});

test('alerte aux Admin : seulement à 5 fois le seuil, une fois par heure et par compte et par fonction', async () => {
  const { obs, horloge, alertes } = observateur();
  const palier = SEUIL * MULTIPLE_ALERTE_ADMIN;
  for (let i = 0; i < palier - 1; i++) await obs.observer('creerPaiement', 'awa');
  assert.equal(alertes.length, 0, 'un fort dépassement du seuil, mais pas encore au palier');
  await obs.observer('creerPaiement', 'awa');
  assert.equal(alertes.length, 1);
  assert.deepEqual(
    { uid: alertes[0].uid, fonction: alertes[0].fonction, appels: alertes[0].appels },
    { uid: 'awa', fonction: 'creerPaiement', appels: palier },
  );
  for (let i = 0; i < 100; i++) await obs.observer('creerPaiement', 'awa');
  assert.equal(alertes.length, 1, 'pas de seconde alerte dans l\'heure');

  horloge.t += 61 * 60 * 1000;
  for (let i = 0; i < palier; i++) await obs.observer('creerPaiement', 'awa');
  assert.equal(alertes.length, 2, 'une heure plus tard, une nouvelle alerte');

  for (let i = 0; i < palier; i++) await obs.observer('creerPaiement', 'fatou');
  assert.equal(alertes.length, 3, 'un autre compte a sa propre alerte');
});

test('l\'alerte aux Admin qui échoue ne fait jamais échouer l\'appel', async () => {
  const { obs } = observateur(async () => {
    throw new Error('FCM en panne');
  });
  let dernier = false;
  for (let i = 0; i < SEUIL * MULTIPLE_ALERTE_ADMIN; i++) dernier = await obs.observer('creerPaiement', 'awa');
  assert.equal(dernier, true);
  assert.equal(erreurs.length, 1);
});

test('mémoire bornée : au-delà de 5000 comptes, ceux qui ont cessé d\'appeler sont oubliés', async () => {
  const { obs, horloge } = observateur();
  for (let i = 0; i < 5001; i++) await obs.observer('creerPaiement', `compte${i}`);
  horloge.t += FENETRE_MS * 2;
  await obs.observer('creerPaiement', 'nouveau');
  const memorises = (obs as unknown as { appels: Map<string, number[]> }).appels.size;
  assert.ok(memorises < 10, `${memorises} comptes encore en mémoire`);
});

test('e-mail non vérifié : une ligne d\'information, rien pour un e-mail vérifié ni sans connexion, jamais d\'erreur', () => {
  observerEmail('creerPaiement', { uid: 'awa', token: { email_verified: true } });
  observerEmail('creerPaiement', undefined);
  assert.equal(informations.length, 0);
  observerEmail('creerRecharge', { uid: 'fatou', token: { email_verified: false } });
  observerEmail('demanderRetrait', { uid: 'ibou', token: {} });
  assert.deepEqual(
    informations.map(([texte, d]) => [texte, d?.fonction, d?.uid]),
    [
      ['Observation : e-mail non vérifié', 'creerRecharge', 'fatou'],
      ['Observation : e-mail non vérifié', 'demanderRetrait', 'ibou'],
    ],
  );
  assert.doesNotThrow(() => observerEmail('x', { uid: 'a', token: null as never }));
});

test('chaque fonction observée dans index.ts a ses règles, et chaque règle est utilisée (une faute de frappe n\'observerait rien)', () => {
  const source = readFileSync(path.join(__dirname, '..', '..', 'src', 'index.ts'), 'utf8');
  const utilisees = [...source.matchAll(/sansRetarder\(frequence\.observer\('([A-Za-z]+)'/g)].map((m) => m[1]).sort();
  assert.deepEqual(utilisees, Object.keys(REGLES_FREQUENCE).sort());
  for (const nom of utilisees) {
    assert.match(source, new RegExp(`export const ${nom} = onCall`), `${nom} n'est pas une fonction exportée du serveur`);
  }
});

test('index.ts : l\'observation ne remplace aucune réponse (le résultat des fonctions d\'origine est rendu tel quel)', () => {
  const source = readFileSync(path.join(__dirname, '..', '..', 'src', 'index.ts'), 'utf8');
  // Les gestes sensibles de l'Admin rendent le résultat de la fonction d'origine, pas celui de l'observation.
  assert.match(source, /const resultat = await ajusterCore\([^\n]*\n\s+await sansRetarder\(observerAjustement\([^\n]*\n\s+return resultat;/);
  assert.match(source, /const resultat = await traiterRetraitCore\([^\n]*\n\s+await sansRetarder\(\s*observerRetraitTraite\([\s\S]*?\n\s+return resultat;/);
  assert.match(source, /const demande = await creerPaiementCore\([\s\S]*?\);\n\s+await sansRetarder\(observerCommandesEnAttente\([^\n]*\n\s+return demande;/);
});

test('sansRetarder : une observation lente ou en panne ne retarde ni ne fait échouer la réponse', async () => {
  // Rapide : rendu aussitôt, sans avertissement.
  await sansRetarder(Promise.resolve('ok'), 50);
  assert.equal(avertissements.length, 0);

  // Qui ne finit jamais : on n'attend pas plus que le délai, et on le dit.
  const debut = Date.now();
  await sansRetarder(new Promise(() => {}), 60);
  const attente = Date.now() - debut;
  assert.ok(attente >= 50 && attente < 1000, `attente de ${attente} ms`);
  assert.equal(avertissements.length, 1);
  assert.match(avertissements[0][0], /Observation trop lente/);

  // En erreur : journalisée, jamais remontée.
  await assert.doesNotReject(sansRetarder(Promise.reject(new Error('panne')), 50));
  assert.equal(erreurs.length, 1);
});
