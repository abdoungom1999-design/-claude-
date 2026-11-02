// Retraits du solde Sprint (lot B) sur l'émulateur Firestore :
// npm run test:emulateur (lance l'émulateur, puis ces tests).
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import {
  DEBUT_ARGENT_REEL_ORANGE,
  demanderRetrait as demanderRetraitCore,
  infosRetrait,
  RETRAIT_MAX_JOUR_FCFA,
  RETRAIT_MIN_FCFA,
  traiterRetrait,
} from '../src/retraits';

const midi = new Date(Date.UTC(2026, 10, 2, 12));
const lendemain = new Date(Date.UTC(2026, 10, 3, 8));
const avantProduction = new Date(DEBUT_ARGENT_REEL_ORANGE.getTime() - 60_000);

let app: App;
let db: Firestore;

const demander = (uid: string | undefined, donnees: unknown, { ouverts = true, le = midi } = {}) =>
  demanderRetraitCore(db, uid, donnees, le, undefined, ouverts);

const demande = (extra: Record<string, unknown> = {}) => ({ montantFcfa: 1500, moyen: 'ORANGE_MONEY', numero: '77 123 45 67', ...extra });

const verser = (retraitId: string, extra: Record<string, unknown> = {}) =>
  traiterRetrait(db, 'admin', { retraitId, decision: 'verse', fraisFcfa: 0, ...extra }, midi);

async function code(promesse: Promise<unknown>): Promise<string> {
  try {
    await promesse;
  } catch (e) {
    return (e as { code?: string }).code ?? String(e);
  }
  return assert.fail('aurait dû être refusé');
}

async function refus(promesse: Promise<unknown>): Promise<{ code: string; message: string; raison?: string }> {
  try {
    await promesse;
  } catch (e) {
    const err = e as { code: string; message: string; details?: { raison?: string } };
    return { code: err.code, message: err.message, raison: err.details?.raison };
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

let numeroMouvement = 0;

/** Mouvement écrit comme le serveur l'écrit (solde mis à jour, livre cohérent). */
async function mouvement(uid: string, type: string, montantFcfa: number, reference: string | null): Promise<void> {
  const solde = (await soldeDe(uid)) + montantFcfa;
  await db.doc(`portefeuilles/${uid}`).set({ soldeFcfa: solde }, { merge: true });
  await db.doc(`portefeuilles/${uid}/mouvements/m${++numeroMouvement}`).set({
    type,
    montantFcfa,
    soldeApresFcfa: solde,
    reference,
    creeLe: Timestamp.fromDate(midi),
  });
}

/** Recharge créditée, payée chez [fournisseur] (« orange_money » en production par défaut : argent réel). */
async function recharger(uid: string, montantFcfa: number, { fournisseur = 'orange_money', le = midi } = {}): Promise<void> {
  const id = `rch_${uid}_${++numeroMouvement}`;
  await db.doc(`recharges/${id}`).set({ clientId: uid, fournisseur, montantFcfa, statut: 'reussie', creeLe: Timestamp.fromDate(le) });
  await mouvement(uid, 'recharge', montantFcfa, id);
}

/** Commande payée chez [fournisseur], remboursée sur le solde (ou débitée du solde si « portefeuille »). */
async function commande(uid: string, fournisseur: string, le = midi): Promise<string> {
  const id = `cmd${++numeroMouvement}`;
  await db.doc(`commandes/${id}`).set({ clientId: uid, fournisseur, creeLe: Timestamp.fromDate(le) });
  return id;
}

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' }, 'retraits');
  db = getFirestore(app);
});

after(() => deleteApp(app));

beforeEach(async () => {
  for (const nom of ['users', 'retraits', 'journal_admin', 'recharges', 'commandes']) await db.recursiveDelete(db.collection(nom));
  for (const uid of ['awa', 'fatou']) await db.recursiveDelete(db.doc(`portefeuilles/${uid}`));
  await db.doc('users/awa').set({ role: 'client', nom: 'Awa Ndiaye', telephone: '+221 77 123 45 67' });
  await db.doc('users/fatou').set({ role: 'client' });
  await db.doc('users/moussa').set({ role: 'conducteur', statutValidation: 'valide' });
  await db.doc('users/banni').set({ role: 'client', statutCompte: 'banni' });
  await db.doc('users/admin').set({ role: 'admin' });
  await recharger('awa', 5000);
});

test('demande : montant réservé aussitôt (débité du solde), envoi attendu sous 48 h, une seule demande à la fois, livre cohérent', async () => {
  const { retraitId, soldeFcfa } = await demander('awa', demande());
  assert.match(retraitId, /^rtr_[0-9a-f]{24}$/);
  assert.equal(soldeFcfa, 3500);
  assert.equal(await soldeDe('awa'), 3500);
  const r = (await db.doc(`retraits/${retraitId}`).get()).data()!;
  assert.deepEqual(
    { clientId: r.clientId, montantFcfa: r.montantFcfa, moyen: r.moyen, numero: r.numero, statut: r.statut, jour: r.jour },
    { clientId: 'awa', montantFcfa: 1500, moyen: 'ORANGE_MONEY', numero: '771234567', statut: 'demande', jour: '2026-11-02' },
  );
  assert.equal((r.aVerserAvant as Timestamp).toMillis() - (r.creeLe as Timestamp).toMillis(), 48 * 3600_000);
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
  assert.equal(await code(demander('awa', demande(), { ouverts: false })), 'failed-precondition');
  assert.equal(await code(demander(undefined, demande())), 'unauthenticated');
  assert.equal(await code(demander('moussa', demande())), 'permission-denied');
  assert.equal(await code(demander('admin', demande())), 'permission-denied');
  assert.equal(await code(demander('banni', demande())), 'permission-denied');
  assert.equal(await code(demander('awa', demande({ montantFcfa: 5001 }))), 'failed-precondition');
  for (const invalide of [
    { montantFcfa: RETRAIT_MIN_FCFA - 1 },
    { montantFcfa: RETRAIT_MAX_JOUR_FCFA + 1 },
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

test('numéro : indicatif +221 ou 00221, espaces, points et tirets acceptés ; Wave aussi ; autre numéro signalé', async () => {
  const { retraitId } = await demander('awa', demande({ numero: '+221 70.123-45-67', moyen: 'WAVE', montantFcfa: 5000 }));
  const r = (await db.doc(`retraits/${retraitId}`).get()).data()!;
  assert.equal(r.numero, '701234567');
  assert.equal(r.moyen, 'WAVE');
  assert.equal(r.numeroDuCompte, false, 'autre numéro que celui du compte : signalé à l\'Admin');
  assert.equal(await soldeDe('awa'), 0);
  // Profil sans nom ni téléphone : « Client », numéro forcément différent.
  await recharger('fatou', 1000);
  const autre = (await db.doc(`retraits/${(await demander('fatou', demande({ montantFcfa: 1000 }))).retraitId}`).get()).data()!;
  assert.deepEqual([autre.nomClient, autre.numeroDuCompte], ['Client', false]);
});

test('argent de test (faux Wave, bac à sable d\'Orange Money) : paie des courses, ne se retire jamais', async () => {
  await recharger('fatou', 20000, { fournisseur: 'simulation' });
  await recharger('fatou', 3000, { fournisseur: 'orange_money', le: avantProduction });
  const r = await refus(demander('fatou', demande({ montantFcfa: 1000 })));
  assert.deepEqual([r.code, r.raison], ['failed-precondition', 'argent_test']);
  assert.match(r.message, /mode test/);
  assert.equal(await soldeDe('fatou'), 23000);
  assert.equal((await db.collection('retraits').get()).size, 0);
  const infos = await infosRetrait(db, 'fatou', midi);
  assert.deepEqual([infos.soldeFcfa, infos.retirableFcfa, infos.maximumFcfa], [23000, 0, 0]);
});

test('argent réel : recharges et remboursements Orange Money en production ; courses payées avec le solde comptées d\'abord dessus', async () => {
  // 5 000 réels (Orange Money) + 10 000 de test (faux Wave).
  await recharger('awa', 10000, { fournisseur: 'simulation' });
  // Course de 3 000 payée avec le solde : comptée sur l'argent réel (prudence).
  const courseSolde = await commande('awa', 'portefeuille');
  await mouvement('awa', 'paiement_course', -3000, courseSolde);
  assert.equal((await infosRetrait(db, 'awa', midi)).retirableFcfa, 2000);
  // Course payée avec le solde puis remboursée : son débit est annulé.
  await mouvement('awa', 'remboursement', 3000, courseSolde);
  assert.equal((await infosRetrait(db, 'awa', midi)).retirableFcfa, 5000);
  // Course payée par Orange Money (production) et remboursée sur le solde : argent réel.
  await mouvement('awa', 'remboursement', 2500, await commande('awa', 'orange_money'));
  // … mais pas un remboursement de la période du bac à sable.
  await mouvement('awa', 'remboursement', 4000, await commande('awa', 'orange_money', avantProduction));
  assert.equal((await infosRetrait(db, 'awa', midi)).retirableFcfa, 7500);
  // Geste commercial de l'Admin : ne se retire pas ; un ajustement négatif se déduit.
  await mouvement('awa', 'ajustement_admin', 1000, null);
  await mouvement('awa', 'ajustement_admin', -500, null);
  const infos = await infosRetrait(db, 'awa', midi);
  assert.deepEqual([infos.soldeFcfa, infos.retirableFcfa, infos.maximumFcfa, infos.enCours], [22000, 7000, 7000, false]);
  // Au-delà de l'argent réel : refusé, avec ce qui est possible.
  const r = await refus(demander('awa', demande({ montantFcfa: 7500 })));
  assert.deepEqual([r.code, r.raison], ['failed-precondition', 'argent_test']);
  assert.match(r.message, /7 000 FCFA au plus/);
  await demander('awa', demande({ montantFcfa: 7000 }));
  await verifierLivre('awa');
  const apres = await infosRetrait(db, 'awa', midi);
  assert.deepEqual([apres.soldeFcfa, apres.retirableFcfa, apres.enCours, apres.maximumFcfa], [15000, 0, true, 0]);
});

test('plafond de 50 000 FCFA par jour et par client (refusés exclus) ; de nouveau possible le lendemain', async () => {
  await recharger('awa', 115000);
  const premier = (await demander('awa', demande({ montantFcfa: 30000 }))).retraitId;
  await verser(premier, { fraisFcfa: 300 });
  const trop = await refus(demander('awa', demande({ montantFcfa: 25000 })));
  assert.deepEqual([trop.code, trop.raison], ['failed-precondition', 'plafond_jour']);
  assert.match(trop.message, /encore retirer 20 000 FCFA aujourd'hui/);
  assert.equal((await infosRetrait(db, 'awa', midi)).resteDuJourFcfa, 20000);
  // Un retrait refusé ne compte pas : son montant est revenu sur le solde.
  const refuse = (await demander('awa', demande({ montantFcfa: 20000 }))).retraitId;
  await traiterRetrait(db, 'admin', { retraitId: refuse, decision: 'refuse', motif: 'Numéro injoignable' }, midi);
  const second = (await demander('awa', demande({ montantFcfa: 20000 }))).retraitId;
  await verser(second);
  const atteint = await refus(demander('awa', demande({ montantFcfa: 500 })));
  assert.equal(atteint.raison, 'plafond_jour');
  assert.match(atteint.message, /atteint : réessayez demain/);
  // Le lendemain (minuit à Dakar = UTC passé) : plafond de nouveau entier.
  const infos = await infosRetrait(db, 'awa', lendemain);
  assert.deepEqual([infos.resteDuJourFcfa, infos.maximumFcfa], [50000, 50000]);
  await demander('awa', demande({ montantFcfa: 50000 }), { le: lendemain });
  assert.equal(await soldeDe('awa'), 120000 - 30000 - 20000 - 50000);
  await verifierLivre('awa');
});

test('Admin : retrait versé, frais de transfert déduits (payés par le client) et référence ; journalisé ; une seule fois', async () => {
  const { retraitId } = await demander('awa', demande());
  assert.deepEqual(await verser(retraitId, { fraisFcfa: 15, reference: ' MP261102.1200.A00001 ' }), { statut: 'verse' });
  const r = (await db.doc(`retraits/${retraitId}`).get()).data()!;
  assert.deepEqual(
    [r.statut, r.traitePar, r.referenceVersement, r.fraisFcfa, r.montantVerseFcfa],
    ['verse', 'admin', 'MP261102.1200.A00001', 15, 1485],
  );
  assert.equal(await soldeDe('awa'), 3500);
  await verifierLivre('awa');
  const journal = (await db.collection('journal_admin').get()).docs.map((d) => d.data());
  assert.deepEqual(
    journal.map((j) => [j.action, j.clientId, j.retraitId, j.montantFcfa, j.fraisFcfa, j.montantVerseFcfa]),
    [['retrait_verse', 'awa', retraitId, 1500, 15, 1485]],
  );
  assert.equal(await code(traiterRetrait(db, 'admin', { retraitId, decision: 'refuse', motif: 'x' }, midi)), 'failed-precondition');
  // Le client peut en demander un nouveau.
  await demander('awa', demande({ montantFcfa: 500 }));
  assert.equal(await soldeDe('awa'), 3000);
});

test('Admin : frais obligatoires au versement (0 s\'il n\'y en a pas), jamais au-delà de 10 % (100 FCFA au moins)', async () => {
  const { retraitId } = await demander('awa', demande({ montantFcfa: 500 }));
  for (const frais of [undefined, -1, 2.5, '10']) {
    assert.equal(await code(verser(retraitId, { fraisFcfa: frais })), 'invalid-argument', String(frais));
  }
  assert.equal(await code(verser(retraitId, { fraisFcfa: 101 })), 'invalid-argument');
  assert.equal((await db.doc(`retraits/${retraitId}`).get()).get('statut'), 'demande');
  await verser(retraitId, { fraisFcfa: 100 });
  assert.equal((await db.doc(`retraits/${retraitId}`).get()).get('montantVerseFcfa'), 400);
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
  // Rendu : de nouveau retirable.
  assert.equal((await infosRetrait(db, 'awa', midi)).retirableFcfa, 5000);
  assert.equal(await code(traiterRetrait(db, 'admin', { retraitId, decision: 'refuse', motif: 'encore' }, midi)), 'failed-precondition');
  assert.equal(await soldeDe('awa'), 5000);
});

test('traitement réservé à l\'Admin ; retrait inconnu ou invalide refusé ; infos réservées au client', async () => {
  const { retraitId } = await demander('awa', demande());
  assert.equal(await code(traiterRetrait(db, 'awa', { retraitId, decision: 'verse', fraisFcfa: 0 }, midi)), 'permission-denied');
  assert.equal(await code(traiterRetrait(db, undefined, { retraitId, decision: 'verse', fraisFcfa: 0 }, midi)), 'unauthenticated');
  assert.equal(await code(traiterRetrait(db, 'admin', { retraitId, decision: 'peut-etre' }, midi)), 'invalid-argument');
  assert.equal(await code(traiterRetrait(db, 'admin', { retraitId: '../users/awa', decision: 'verse', fraisFcfa: 0 }, midi)), 'invalid-argument');
  assert.equal(
    await code(traiterRetrait(db, 'admin', { retraitId: `rtr_${'0'.repeat(24)}`, decision: 'verse', fraisFcfa: 0 }, midi)),
    'not-found',
  );
  assert.equal((await db.doc(`retraits/${retraitId}`).get()).get('statut'), 'demande');
  assert.equal(await code(infosRetrait(db, undefined, midi)), 'unauthenticated');
  assert.equal(await code(infosRetrait(db, 'moussa', midi)), 'permission-denied');
  assert.equal(await code(infosRetrait(db, 'banni', midi)), 'permission-denied');
});
