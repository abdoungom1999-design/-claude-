// Retraits du solde Sprint (lot B) sur l'émulateur Firestore :
// npm run test:emulateur (lance l'émulateur, puis ces tests).
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { demanderRetrait as demanderRetraitCore, RETRAIT_MIN_FCFA, traiterRetrait } from '../src/retraits';

const midi = new Date(Date.UTC(2026, 10, 2, 12));

let app: App;
let db: Firestore;

/** Retraits ouverts pour ces tests (le réglage en service reste fermé jusqu'au go du client). */
const demander = (uid: string | undefined, donnees: unknown, ouverts = true) =>
  demanderRetraitCore(db, uid, donnees, midi, undefined, ouverts);

const demande = (extra: Record<string, unknown> = {}) => ({ montantFcfa: 1500, moyen: 'ORANGE_MONEY', numero: '77 123 45 67', ...extra });

async function code(promesse: Promise<unknown>): Promise<string> {
  try {
    await promesse;
  } catch (e) {
    return (e as { code?: string }).code ?? String(e);
  }
  return assert.fail('aurait dû être refusé');
}

const soldeDe = async (uid: string) => ((await db.doc(`portefeuilles/${uid}`).get()).get('soldeFcfa') as number | undefined) ?? 0;
const mouvements = async (uid: string) =>
  (await db.collection(`portefeuilles/${uid}/mouvements`).get()).docs.map((d) => ({ id: d.id, ...d.data() }) as Record<string, unknown>);

/** Invariant du livre : la somme des mouvements est exactement le solde. */
async function verifierLivre(uid: string): Promise<void> {
  const somme = (await mouvements(uid)).reduce((total, m) => total + (m.montantFcfa as number), 0);
  assert.equal(somme, await soldeDe(uid), `livre incohérent pour ${uid}`);
}

/** Solde de départ, avec son mouvement (le livre reste cohérent). */
async function crediter(uid: string, montantFcfa: number): Promise<void> {
  await db.doc(`portefeuilles/${uid}`).set({ soldeFcfa: montantFcfa });
  await db.doc(`portefeuilles/${uid}/mouvements/recharge_test`).set({
    type: 'recharge',
    montantFcfa,
    soldeApresFcfa: montantFcfa,
    reference: 'rch_test',
    creeLe: Timestamp.fromDate(midi),
  });
}

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' }, 'retraits');
  db = getFirestore(app);
});

after(() => deleteApp(app));

beforeEach(async () => {
  for (const nom of ['users', 'retraits', 'journal_admin']) await db.recursiveDelete(db.collection(nom));
  for (const uid of ['awa', 'fatou']) await db.recursiveDelete(db.doc(`portefeuilles/${uid}`));
  await db.doc('users/awa').set({ role: 'client', nom: 'Awa Ndiaye', telephone: '+221 77 123 45 67' });
  await db.doc('users/fatou').set({ role: 'client' });
  await db.doc('users/moussa').set({ role: 'conducteur', statutValidation: 'valide' });
  await db.doc('users/banni').set({ role: 'client', statutCompte: 'banni' });
  await db.doc('users/admin').set({ role: 'admin' });
  await crediter('awa', 5000);
});

test('demande : montant réservé aussitôt (débité du solde), une seule demande à la fois, livre cohérent', async () => {
  const { retraitId, soldeFcfa } = await demander('awa', demande());
  assert.match(retraitId, /^rtr_[0-9a-f]{24}$/);
  assert.equal(soldeFcfa, 3500);
  assert.equal(await soldeDe('awa'), 3500);
  const r = (await db.doc(`retraits/${retraitId}`).get()).data()!;
  assert.deepEqual(
    { clientId: r.clientId, montantFcfa: r.montantFcfa, moyen: r.moyen, numero: r.numero, statut: r.statut },
    { clientId: 'awa', montantFcfa: 1500, moyen: 'ORANGE_MONEY', numero: '771234567', statut: 'demande' },
  );
  // Pour l'Admin : nom du compte, et numéro de réception = numéro du compte.
  assert.deepEqual([r.nomClient, r.numeroDuCompte], ['Awa Ndiaye', true]);
  const mvt = (await mouvements('awa')).find((m) => m.id === `retrait_${retraitId}`)!;
  assert.deepEqual([mvt.type, mvt.montantFcfa, mvt.reference, mvt.note], ['retrait', -1500, retraitId, 'Orange Money']);
  await verifierLivre('awa');
  // Seconde demande avant le traitement de la première : refusée, rien ne bouge.
  assert.equal(await code(demander('awa', demande({ montantFcfa: 500 }))), 'failed-precondition');
  assert.equal(await soldeDe('awa'), 3500);
});

test('demande refusée : retraits fermés, non connecté, pas un client, compte banni, solde insuffisant, champs invalides', async () => {
  assert.equal(await code(demander('awa', demande(), false)), 'failed-precondition');
  assert.equal(await code(demander(undefined, demande())), 'unauthenticated');
  assert.equal(await code(demander('moussa', demande())), 'permission-denied');
  assert.equal(await code(demander('admin', demande())), 'permission-denied');
  assert.equal(await code(demander('banni', demande())), 'permission-denied');
  assert.equal(await code(demander('awa', demande({ montantFcfa: 5001 }))), 'failed-precondition');
  for (const invalide of [
    { montantFcfa: RETRAIT_MIN_FCFA - 1 },
    { montantFcfa: 1000.5 },
    { montantFcfa: '1000' },
    { moyen: 'PORTEFEUILLE' },
    { moyen: undefined },
    { numero: '33 6 12 34 56 78' },
    { numero: '771234' },
    { numero: '+221 33 123 45 67' },
  ]) {
    assert.equal(await code(demander('awa', demande(invalide))), 'invalid-argument', JSON.stringify(invalide));
  }
  assert.equal(await soldeDe('awa'), 5000);
  assert.equal((await db.collection('retraits').get()).size, 0);
});

test('numéro : indicatif +221 ou 00221, espaces, points et tirets acceptés ; Wave aussi', async () => {
  const { retraitId } = await demander('awa', demande({ numero: '+221 70.123-45-67', moyen: 'WAVE', montantFcfa: 5000 }));
  const r = (await db.doc(`retraits/${retraitId}`).get()).data()!;
  assert.equal(r.numero, '701234567');
  assert.equal(r.moyen, 'WAVE');
  assert.equal(r.numeroDuCompte, false, 'autre numéro que celui du compte : signalé à l\'Admin');
  assert.equal(await soldeDe('awa'), 0);
  // Profil sans nom ni téléphone : « Client », numéro forcément différent.
  await crediter('fatou', 1000);
  const autre = (await db.doc(`retraits/${(await demander('fatou', demande({ montantFcfa: 1000 }))).retraitId}`).get()).data()!;
  assert.deepEqual([autre.nomClient, autre.numeroDuCompte], ['Client', false]);
});

test('Admin : retrait versé (référence du transfert), journalisé ; le solde ne bouge plus ; une seule fois', async () => {
  const { retraitId } = await demander('awa', demande());
  assert.deepEqual(await traiterRetrait(db, 'admin', { retraitId, decision: 'verse', reference: ' MP261102.1200.A00001 ' }, midi), {
    statut: 'verse',
  });
  const r = (await db.doc(`retraits/${retraitId}`).get()).data()!;
  assert.deepEqual([r.statut, r.traitePar, r.referenceVersement], ['verse', 'admin', 'MP261102.1200.A00001']);
  assert.equal(await soldeDe('awa'), 3500);
  await verifierLivre('awa');
  const journal = (await db.collection('journal_admin').get()).docs.map((d) => d.data());
  assert.deepEqual(
    journal.map((j) => [j.action, j.clientId, j.retraitId, j.montantFcfa]),
    [['retrait_verse', 'awa', retraitId, 1500]],
  );
  assert.equal(await code(traiterRetrait(db, 'admin', { retraitId, decision: 'refuse', motif: 'x' }, midi)), 'failed-precondition');
  // Le client peut en demander un nouveau.
  await demander('awa', demande({ montantFcfa: 500 }));
  assert.equal(await soldeDe('awa'), 3000);
});

test('Admin : retrait refusé (motif obligatoire), montant rendu sur le solde, journalisé ; une seule fois', async () => {
  const { retraitId } = await demander('awa', demande());
  assert.equal(await code(traiterRetrait(db, 'admin', { retraitId, decision: 'refuse', motif: '  ' }, midi)), 'invalid-argument');
  await traiterRetrait(db, 'admin', { retraitId, decision: 'refuse', motif: 'Numéro injoignable' }, midi);
  const r = (await db.doc(`retraits/${retraitId}`).get()).data()!;
  assert.deepEqual([r.statut, r.motifRefus], ['refuse', 'Numéro injoignable']);
  assert.equal(await soldeDe('awa'), 5000);
  const rendu = (await mouvements('awa')).find((m) => m.id === `retrait_rendu_${retraitId}`)!;
  assert.deepEqual([rendu.type, rendu.montantFcfa, rendu.note], ['retrait_rendu', 1500, 'Numéro injoignable']);
  await verifierLivre('awa');
  assert.equal(await code(traiterRetrait(db, 'admin', { retraitId, decision: 'refuse', motif: 'encore' }, midi)), 'failed-precondition');
  assert.equal(await soldeDe('awa'), 5000);
});

test('traitement réservé à l\'Admin ; retrait inconnu ou invalide refusé', async () => {
  const { retraitId } = await demander('awa', demande());
  assert.equal(await code(traiterRetrait(db, 'awa', { retraitId, decision: 'verse' }, midi)), 'permission-denied');
  assert.equal(await code(traiterRetrait(db, undefined, { retraitId, decision: 'verse' }, midi)), 'unauthenticated');
  assert.equal(await code(traiterRetrait(db, 'admin', { retraitId, decision: 'peut-etre' }, midi)), 'invalid-argument');
  assert.equal(await code(traiterRetrait(db, 'admin', { retraitId: '../users/awa', decision: 'verse' }, midi)), 'invalid-argument');
  assert.equal(
    await code(traiterRetrait(db, 'admin', { retraitId: `rtr_${'0'.repeat(24)}`, decision: 'verse' }, midi)),
    'not-found',
  );
  assert.equal((await db.doc(`retraits/${retraitId}`).get()).get('statut'), 'demande');
});
