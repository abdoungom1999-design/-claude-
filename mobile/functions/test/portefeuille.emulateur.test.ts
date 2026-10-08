// Tests du Portefeuille Sprint sur l'émulateur Firestore :
// npm run test:emulateur (lance l'émulateur, puis ces tests).
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { ajusterPortefeuille, rembourserCourseAdmin } from '../src/admin';
import { calculDistance } from '../src/distances';
import { FournisseurSimule, type EvenementPaiement } from '../src/fournisseurs';
import type { ClientGoogle } from '../src/google';
import { annulerCourse, creerPaiement as creerPaiementCore, surveiller, traiterEvenement } from '../src/paiements';
import {
  creerRecharge as creerRechargeCore,
  DUREE_RECHARGE_MS,
  PREFIXE_RECHARGE,
  rembourserSurPortefeuille,
  SOLDE_MAX_FCFA,
  surveillerRecharges,
  traiterEvenementRecharge,
} from '../src/portefeuille';

const PLATEAU = { latitude: 14.6928, longitude: -17.4467 };
const ALMADIES = { latitude: 14.7456, longitude: -17.5134 };
const midi = new Date(Date.UTC(2026, 8, 27, 12));
const minutes = (n: number) => new Date(midi.getTime() + n * 60 * 1000);

/** Course de 2 300 FCFA (Plateau -> Almadies, 10,2 km, midi). */
const PRIX = 2300;

const demande = (extra: Record<string, unknown> = {}) => ({
  type: 'PASSAGER',
  depart: PLATEAU,
  arrivee: ALMADIES,
  adresseDepart: 'Plateau',
  adresseArrivee: 'Almadies',
  methodePaiement: 'PORTEFEUILLE',
  prixAttendu: PRIX,
  ...extra,
});

let app: App;
let db: Firestore;
let remboursements: string[];
let fournisseur: FournisseurSimule;

const googleFactice = { itineraire: async () => ({ distanceKm: 10.2 }) } as unknown as ClientGoogle;

const creerPaiement = (uid: string | undefined, donnees: unknown, quand = midi) =>
  creerPaiementCore(db, calculDistance(db, googleFactice, () => quand), fournisseur, uid, donnees, quand);

const creerRecharge = (uid: string | undefined, donnees: unknown, quand = midi) =>
  creerRechargeCore(db, fournisseur, uid, donnees, quand);

async function code(promesse: Promise<unknown>): Promise<string> {
  try {
    await promesse;
  } catch (e) {
    return (e as { code?: string }).code ?? String(e);
  }
  return assert.fail('aurait dû être refusé');
}

const soldeDe = async (uid: string) => ((await db.doc(`portefeuilles/${uid}`).get()).get('soldeFcfa') as number | undefined) ?? 0;
interface Mouvement {
  id: string;
  type: string;
  montantFcfa: number;
  soldeApresFcfa: number;
  reference: string | null;
  note?: string;
}
const mouvements = async (uid: string) =>
  (await db.collection(`portefeuilles/${uid}/mouvements`).get()).docs.map((d) => ({ id: d.id, ...d.data() }) as Mouvement);

/** Invariant du livre : la somme des mouvements est exactement le solde. */
async function verifierLivre(uid: string): Promise<void> {
  const somme = (await mouvements(uid)).reduce((total, m) => total + m.montantFcfa, 0);
  assert.equal(somme, await soldeDe(uid), `livre incohérent pour ${uid}`);
}

async function evenementRecharge(rechargeId: string, extra: Partial<EvenementPaiement> = {}): Promise<EvenementPaiement> {
  const r = (await db.doc(`recharges/${rechargeId}`).get()).data()!;
  return { sessionId: r.sessionPaiementId, commandeId: rechargeId, reussi: true, montantFcfa: r.montantFcfa, devise: 'XOF', ...extra };
}

/** Recharge payée jusqu'au bout : le solde est crédité. */
async function recharger(uid: string, montantFcfa: number, quand = midi): Promise<string> {
  const { rechargeId } = await creerRecharge(uid, { montantFcfa, methodePaiement: 'WAVE' }, quand);
  assert.equal(await traiterEvenementRecharge(db, await evenementRecharge(rechargeId), quand), 'recharge_creditee');
  return rechargeId;
}

const course = async (id: string) => (await db.doc(`courses/${id}`).get()).data()!;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' }, 'portefeuille');
  db = getFirestore(app);
});

after(() => deleteApp(app));

beforeEach(async () => {
  remboursements = [];
  fournisseur = new FournisseurSimule('secret', 'https://page', remboursements);
  for (const nom of ['users', 'courses', 'commandes', 'distances', 'config', 'recharges', 'journal_admin']) {
    const docs = await db.collection(nom).listDocuments();
    await Promise.all(docs.map((d) => d.delete()));
  }
  for (const uid of ['awa', 'fatou']) {
    const mvts = await db.collection(`portefeuilles/${uid}/mouvements`).listDocuments();
    await Promise.all(mvts.map((d) => d.delete()));
    await db.doc(`portefeuilles/${uid}`).delete();
  }
  await db.doc('users/awa').set({ role: 'client', nom: 'Awa' });
  await db.doc('users/fatou').set({ role: 'client', nom: 'Fatou' });
  await db.doc('users/moussa').set({ role: 'conducteur', statutValidation: 'valide' });
  await db.doc('users/banni').set({ role: 'client', statutCompte: 'banni' });
  await db.doc('users/admin').set({ role: 'admin' });
});

// --- Demande de recharge ---------------------------------------------------

test('recharge : demande en attente avec lien de paiement, solde intact', async () => {
  const r = await creerRecharge('awa', { montantFcfa: 5000, methodePaiement: 'WAVE' });
  assert.match(r.rechargeId, new RegExp(`^${PREFIXE_RECHARGE}`));
  assert.match(r.lienPaiement!, /^https:\/\/page\?session=sim_/);
  const d = (await db.doc(`recharges/${r.rechargeId}`).get()).data()!;
  assert.equal(d.clientId, 'awa');
  assert.equal(d.statut, 'en_attente');
  assert.equal(d.montantFcfa, 5000);
  assert.equal(await soldeDe('awa'), 0);
  assert.equal((await mouvements('awa')).length, 0);
});

test('recharge : montants et modes refusés', async () => {
  assert.equal(await code(creerRecharge('awa', { montantFcfa: 499, methodePaiement: 'WAVE' })), 'invalid-argument');
  assert.equal(await code(creerRecharge('awa', { montantFcfa: 100_001, methodePaiement: 'WAVE' })), 'invalid-argument');
  assert.equal(await code(creerRecharge('awa', { montantFcfa: 1000.5, methodePaiement: 'WAVE' })), 'invalid-argument');
  assert.equal(await code(creerRecharge('awa', { montantFcfa: '1000', methodePaiement: 'WAVE' })), 'invalid-argument');
  assert.equal(await code(creerRecharge('awa', { montantFcfa: -1000, methodePaiement: 'WAVE' })), 'invalid-argument');
  assert.equal(await code(creerRecharge('awa', { montantFcfa: 1000, methodePaiement: 'PORTEFEUILLE' })), 'invalid-argument');
  assert.equal(await code(creerRecharge('awa', { montantFcfa: 1000, methodePaiement: 'CARTE' })), 'invalid-argument');
  assert.equal(await code(creerRecharge('awa', null)), 'invalid-argument');
  // Bornes acceptées.
  await creerRecharge('awa', { montantFcfa: 500, methodePaiement: 'WAVE' });
  await creerRecharge('awa', { montantFcfa: 100_000, methodePaiement: 'WAVE' });
});

test('recharge : Orange Money fermé (pas de recharge, pas de session de paiement)', async () => {
  let sessions = 0;
  const reel = fournisseur.creerSession.bind(fournisseur);
  fournisseur.creerSession = async () => {
    sessions++;
    return reel();
  };
  assert.equal(await code(creerRecharge('awa', { montantFcfa: 5000, methodePaiement: 'ORANGE_MONEY' })), 'failed-precondition');
  assert.equal((await db.collection('recharges').get()).size, 0);
  assert.equal(sessions, 0);
  assert.equal(await soldeDe('awa'), 0);
});

test('recharge : connexion, rôle client et compte actif exigés', async () => {
  assert.equal(await code(creerRecharge(undefined, { montantFcfa: 1000, methodePaiement: 'WAVE' })), 'unauthenticated');
  assert.equal(await code(creerRecharge('inconnu', { montantFcfa: 1000, methodePaiement: 'WAVE' })), 'permission-denied');
  assert.equal(await code(creerRecharge('moussa', { montantFcfa: 1000, methodePaiement: 'WAVE' })), 'permission-denied');
  assert.equal(await code(creerRecharge('admin', { montantFcfa: 1000, methodePaiement: 'WAVE' })), 'permission-denied');
  assert.equal(await code(creerRecharge('banni', { montantFcfa: 1000, methodePaiement: 'WAVE' })), 'permission-denied');
  assert.equal((await db.collection('recharges').get()).size, 0);
});

test('recharge : plafond du solde à 200 000 FCFA', async () => {
  await recharger('awa', 100_000);
  await recharger('awa', 90_000);
  assert.equal(await soldeDe('awa'), 190_000);
  assert.equal(await code(creerRecharge('awa', { montantFcfa: 10_001, methodePaiement: 'WAVE' })), 'failed-precondition');
  await recharger('awa', 10_000);
  assert.equal(await soldeDe('awa'), SOLDE_MAX_FCFA);
  assert.equal(await code(creerRecharge('awa', { montantFcfa: 500, methodePaiement: 'WAVE' })), 'failed-precondition');
  await verifierLivre('awa');
});

test('recharge : au plus 5 recharges en attente par client', async () => {
  for (let i = 0; i < 5; i++) await creerRecharge('awa', { montantFcfa: 500, methodePaiement: 'WAVE' });
  assert.equal(await code(creerRecharge('awa', { montantFcfa: 500, methodePaiement: 'WAVE' })), 'resource-exhausted');
  // Un autre client n'est pas concerné ; les recharges expirées ne comptent plus.
  await creerRecharge('fatou', { montantFcfa: 500, methodePaiement: 'WAVE' });
  await creerRecharge('awa', { montantFcfa: 500, methodePaiement: 'WAVE' }, new Date(midi.getTime() + DUREE_RECHARGE_MS + 1000));
});

// --- Confirmation du fournisseur ------------------------------------------

test('webhook : la recharge crédite le solde une seule fois, même rejouée', async () => {
  const { rechargeId } = await creerRecharge('awa', { montantFcfa: 5000, methodePaiement: 'WAVE' });
  const ev = await evenementRecharge(rechargeId);
  assert.equal(await traiterEvenementRecharge(db, ev, midi), 'recharge_creditee');
  assert.equal(await traiterEvenementRecharge(db, ev, minutes(1)), 'deja_traite');
  assert.equal(await traiterEvenementRecharge(db, ev, minutes(2)), 'deja_traite');
  assert.equal(await soldeDe('awa'), 5000);
  const m = await mouvements('awa');
  assert.equal(m.length, 1);
  assert.deepEqual(
    { id: m[0].id, type: m[0].type, montantFcfa: m[0].montantFcfa },
    { id: `recharge_${rechargeId}`, type: 'recharge', montantFcfa: 5000 },
  );
  assert.equal(m[0].soldeApresFcfa, 5000);
  assert.equal((await db.doc(`recharges/${rechargeId}`).get()).get('statut'), 'reussie');
  await verifierLivre('awa');
});

test('webhook : deux événements simultanés ne créditent qu\'une fois', async () => {
  const { rechargeId } = await creerRecharge('awa', { montantFcfa: 5000, methodePaiement: 'WAVE' });
  const ev = await evenementRecharge(rechargeId);
  // Sous forte concurrence Firestore peut refuser une des deux transactions
  // (le fournisseur réessaiera alors son événement) : jamais deux crédits.
  const resultats = await Promise.allSettled([traiterEvenementRecharge(db, ev, midi), traiterEvenementRecharge(db, ev, midi)]);
  const valeurs = resultats.flatMap((r) => (r.status === 'fulfilled' ? [r.value] : []));
  assert.equal(valeurs.filter((v) => v === 'recharge_creditee').length, 1);
  assert.ok(valeurs.every((v) => v === 'recharge_creditee' || v === 'deja_traite'));
  assert.equal(await traiterEvenementRecharge(db, ev, midi), 'deja_traite');
  assert.equal(await soldeDe('awa'), 5000);
  assert.equal((await mouvements('awa')).length, 1);
});

test('webhook : refus enregistré, jamais crédité ; un succès tardif ensuite est ignoré', async () => {
  const { rechargeId } = await creerRecharge('awa', { montantFcfa: 5000, methodePaiement: 'WAVE' });
  assert.equal(await traiterEvenementRecharge(db, await evenementRecharge(rechargeId, { reussi: false }), midi), 'echec_enregistre');
  assert.equal((await db.doc(`recharges/${rechargeId}`).get()).get('statut'), 'echouee');
  assert.equal(await traiterEvenementRecharge(db, await evenementRecharge(rechargeId), minutes(1)), 'deja_traite');
  assert.equal(await soldeDe('awa'), 0);
});

test('webhook : montant ou devise différents de la demande = anomalie, rien crédité', async () => {
  const a = await creerRecharge('awa', { montantFcfa: 5000, methodePaiement: 'WAVE' });
  assert.equal(await traiterEvenementRecharge(db, await evenementRecharge(a.rechargeId, { montantFcfa: 50_000 }), midi), 'anomalie');
  const b = await creerRecharge('awa', { montantFcfa: 5000, methodePaiement: 'WAVE' });
  assert.equal(await traiterEvenementRecharge(db, await evenementRecharge(b.rechargeId, { devise: 'EUR' }), midi), 'anomalie');
  assert.equal(await soldeDe('awa'), 0);
  assert.equal((await db.doc(`recharges/${a.rechargeId}`).get()).get('statut'), 'anomalie');
});

test('webhook : session inconnue ou qui ne correspond pas à la recharge', async () => {
  const { rechargeId } = await creerRecharge('awa', { montantFcfa: 5000, methodePaiement: 'WAVE' });
  const ev = await evenementRecharge(rechargeId);
  assert.equal(await traiterEvenementRecharge(db, { ...ev, sessionId: 'sim_autre' }, midi), 'inconnue');
  assert.equal(await traiterEvenementRecharge(db, { ...ev, commandeId: `${PREFIXE_RECHARGE}inexistante` }, midi), 'inconnue');
  assert.equal(await soldeDe('awa'), 0);
});

test('webhook : paiement arrivé après l\'expiration = crédité (l\'argent est encaissé)', async () => {
  const { rechargeId } = await creerRecharge('awa', { montantFcfa: 5000, methodePaiement: 'WAVE' });
  assert.equal(await surveillerRecharges(db, new Date(midi.getTime() + DUREE_RECHARGE_MS + 1000)), 1);
  assert.equal((await db.doc(`recharges/${rechargeId}`).get()).get('statut'), 'expiree');
  assert.equal(await traiterEvenementRecharge(db, await evenementRecharge(rechargeId), minutes(30)), 'recharge_creditee');
  assert.equal(await soldeDe('awa'), 5000);
  await verifierLivre('awa');
});

test('webhook : deux recharges concurrentes au-delà du plafond, la seconde est une anomalie visible', async () => {
  const a = await creerRecharge('awa', { montantFcfa: 100_000, methodePaiement: 'WAVE' });
  const b = await creerRecharge('awa', { montantFcfa: 100_000, methodePaiement: 'WAVE' });
  const c = await creerRecharge('awa', { montantFcfa: 100_000, methodePaiement: 'WAVE' });
  assert.equal(await traiterEvenementRecharge(db, await evenementRecharge(a.rechargeId), midi), 'recharge_creditee');
  assert.equal(await traiterEvenementRecharge(db, await evenementRecharge(b.rechargeId), midi), 'recharge_creditee');
  assert.equal(await traiterEvenementRecharge(db, await evenementRecharge(c.rechargeId), midi), 'anomalie');
  assert.equal(await soldeDe('awa'), SOLDE_MAX_FCFA);
  assert.equal((await db.doc(`recharges/${c.rechargeId}`).get()).get('motif'), 'plafond');
  await verifierLivre('awa');
});

test('surveillance : recharge jamais payée expirée, une payée intacte', async () => {
  const jamaisPayee = await creerRecharge('awa', { montantFcfa: 500, methodePaiement: 'WAVE' });
  const payee = await recharger('fatou', 500);
  assert.equal(await surveillerRecharges(db, midi), 0);
  assert.equal(await surveillerRecharges(db, new Date(midi.getTime() + DUREE_RECHARGE_MS + 1000)), 1);
  assert.equal((await db.doc(`recharges/${jamaisPayee.rechargeId}`).get()).get('statut'), 'expiree');
  assert.equal((await db.doc(`recharges/${payee}`).get()).get('statut'), 'reussie');
});

// --- Paiement d'une course avec le solde ----------------------------------

test('course payée avec le solde : débit, commande payée et course créées ensemble', async () => {
  await recharger('awa', 5000);
  const r = await creerPaiement('awa', demande());
  assert.equal(r.lienPaiement, null);
  assert.equal(r.payeParSolde, true);
  assert.equal(r.prixFcfa, PRIX);
  assert.equal(await soldeDe('awa'), 5000 - PRIX);

  const commande = (await db.doc(`commandes/${r.commandeId}`).get()).data()!;
  assert.equal(commande.statut, 'payee');
  assert.equal(commande.fournisseur, 'portefeuille');
  assert.equal(commande.methodePaiement, 'PORTEFEUILLE');
  const c = await course(commande.courseId);
  assert.equal(c.statut, 'en_attente');
  assert.equal(c.clientId, 'awa');
  assert.equal(c.prixFcfa, PRIX);
  assert.equal(c.commandeId, r.commandeId);
  assert.equal(c.modePaiement, 'portefeuille');

  const debit = (await mouvements('awa')).find((m) => m.id === `course_${r.commandeId}`)!;
  assert.deepEqual(
    { type: debit.type, montantFcfa: debit.montantFcfa, soldeApresFcfa: debit.soldeApresFcfa, reference: debit.reference },
    { type: 'paiement_course', montantFcfa: -PRIX, soldeApresFcfa: 5000 - PRIX, reference: r.commandeId },
  );
  await verifierLivre('awa');
});

test('course payée avec le solde : solde exactement égal au prix accepté, solde nul ensuite', async () => {
  await recharger('awa', 2500);
  await adjust('awa', -200);
  assert.equal(await soldeDe('awa'), PRIX);
  await creerPaiement('awa', demande());
  assert.equal(await soldeDe('awa'), 0);
  await verifierLivre('awa');
});

async function adjust(uid: string, montantFcfa: number) {
  return ajusterPortefeuille(db, 'admin', { clientId: uid, montantFcfa, motif: 'test' }, midi);
}

test('solde insuffisant : refus net, rien débité, aucune commande ni course', async () => {
  await recharger('awa', 2000);
  const err = await creerPaiement('awa', demande()).catch((e) => e);
  assert.equal(err.code, 'failed-precondition');
  assert.equal(err.details.raison, 'solde-insuffisant');
  assert.equal(err.details.soldeFcfa, 2000);
  assert.equal(await soldeDe('awa'), 2000);
  assert.equal((await db.collection('commandes').get()).size, 0);
  assert.equal((await db.collection('courses').get()).size, 0);
  assert.equal((await mouvements('awa')).length, 1);
});

test('portefeuille inexistant ou vide : refus, pas de portefeuille créé par erreur', async () => {
  assert.equal(await code(creerPaiement('awa', demande())), 'failed-precondition');
  assert.equal((await db.doc('portefeuilles/awa').get()).exists, false);
});

test('prix modifié entre-temps : refus avant tout débit', async () => {
  await recharger('awa', 5000);
  assert.equal(await code(creerPaiement('awa', demande({ prixAttendu: 1000 }))), 'failed-precondition');
  assert.equal(await soldeDe('awa'), 5000);
  assert.equal((await db.collection('courses').get()).size, 0);
});

test('paiement par solde : connexion et compte actif exigés', async () => {
  await recharger('awa', 5000);
  assert.equal(await code(creerPaiement(undefined, demande())), 'unauthenticated');
  await db.doc('portefeuilles/banni').set({ soldeFcfa: 50_000 });
  assert.equal(await code(creerPaiement('banni', demande())), 'permission-denied');
  assert.equal(await soldeDe('banni'), 50_000);
});

test('on ne dépense jamais le solde d\'un autre client', async () => {
  await recharger('awa', 5000);
  assert.equal(await code(creerPaiement('fatou', demande())), 'failed-precondition');
  assert.equal(await soldeDe('awa'), 5000);
  assert.equal(await soldeDe('fatou'), 0);
});

test('deux commandes simultanées pour un solde qui n\'en couvre qu\'une : une seule passe', async () => {
  await recharger('awa', 3000);
  const resultats = await Promise.allSettled([creerPaiement('awa', demande()), creerPaiement('awa', demande())]);
  assert.equal(resultats.filter((r) => r.status === 'fulfilled').length, 1);
  assert.equal(resultats.filter((r) => r.status === 'rejected').length, 1);
  assert.equal(await soldeDe('awa'), 3000 - PRIX);
  assert.equal((await db.collection('courses').get()).size, 1);
  await verifierLivre('awa');
});

test('le paiement mobile money continue de fonctionner sans toucher au solde', async () => {
  await recharger('awa', 5000);
  const r = await creerPaiement('awa', demande({ methodePaiement: 'WAVE' }));
  assert.match(r.lienPaiement!, /^https:\/\/page\?session=sim_/);
  assert.equal(r.payeParSolde, undefined);
  assert.equal(await soldeDe('awa'), 5000);
  const ev = {
    sessionId: (await db.doc(`commandes/${r.commandeId}`).get()).get('sessionPaiementId'),
    commandeId: r.commandeId,
    reussi: true,
    montantFcfa: PRIX,
    devise: 'XOF',
  };
  assert.equal(await traiterEvenement(db, fournisseur, ev, midi), 'course_creee');
  assert.equal(await soldeDe('awa'), 5000);
  assert.equal((await mouvements('awa')).length, 1);
});

// --- Remboursements sur le solde ------------------------------------------

async function payerParSolde(uid: string): Promise<{ commandeId: string; courseId: string }> {
  const { commandeId } = await creerPaiement(uid, demande());
  return { commandeId, courseId: (await db.doc(`commandes/${commandeId}`).get()).get('courseId') as string };
}

test('annulation par le client : le prix retourne sur le solde, sans appel au fournisseur', async () => {
  await recharger('awa', 5000);
  const { commandeId, courseId } = await payerParSolde('awa');
  assert.equal(await soldeDe('awa'), 5000 - PRIX);
  const r = await annulerCourse(db, fournisseur, 'awa', { courseId }, minutes(1));
  assert.equal(r.rembourse, true);
  assert.equal(await soldeDe('awa'), 5000);
  assert.deepEqual(remboursements, []);
  assert.equal((await db.doc(`commandes/${commandeId}`).get()).get('statut'), 'remboursee');
  assert.ok((await mouvements('awa')).some((m) => m.id === `remboursement_${commandeId}`));
  await verifierLivre('awa');
});

test('remboursement rejoué ou simultané : un seul crédit', async () => {
  await recharger('awa', 5000);
  const { commandeId } = await payerParSolde('awa');
  const ref = db.doc(`commandes/${commandeId}`);
  await Promise.allSettled([
    rembourserSurPortefeuille(db, ref, 'test', minutes(1)),
    rembourserSurPortefeuille(db, ref, 'test', minutes(1)),
  ]);
  await rembourserSurPortefeuille(db, ref, 'test', minutes(2));
  assert.equal(await soldeDe('awa'), 5000);
  assert.equal((await mouvements('awa')).filter((m) => m.id.startsWith('remboursement_')).length, 1);
  await verifierLivre('awa');
});

test('course sans chauffeur au bout de 10 min : annulée et remboursée sur le solde', async () => {
  await recharger('awa', 5000);
  const { courseId } = await payerParSolde('awa');
  // Le serveur horodate la course à l'heure réelle : le temps se compte depuis cet instant.
  const creeLe = ((await course(courseId)).timestamp as { toDate(): Date }).toDate();
  assert.equal((await surveiller(db, fournisseur, new Date(creeLe.getTime() + 9 * 60 * 1000))).sansChauffeur, 0);
  const bilan = await surveiller(db, fournisseur, new Date(creeLe.getTime() + 11 * 60 * 1000));
  assert.equal(bilan.sansChauffeur, 1);
  assert.equal(await soldeDe('awa'), 5000);
  await verifierLivre('awa');
});

test('annulation par le chauffeur : le client est remboursé sur son solde', async () => {
  await recharger('awa', 5000);
  const { courseId } = await payerParSolde('awa');
  await db.doc(`courses/${courseId}`).update({ chauffeurId: 'moussa', statut: 'acceptee' });
  const r = await annulerCourse(db, fournisseur, 'moussa', { courseId, motif: 'panne' }, minutes(1));
  assert.equal(r.rembourse, true);
  assert.equal(await soldeDe('awa'), 5000);
});

test('remboursement Admin d\'une course payée par le solde : sur le solde, message adapté', async () => {
  await recharger('awa', 5000);
  const { commandeId, courseId } = await payerParSolde('awa');
  await db.doc(`courses/${courseId}`).update({ statut: 'annulee', annuleePar: 'systeme' });
  // Le solde est déjà revenu si l'annulation a remboursé ; ici la course est annulée à la main.
  const r = await rembourserCourseAdmin(db, fournisseur, 'admin', { courseId, motif: 'geste commercial' }, minutes(5));
  assert.equal(r.rembourse, true);
  assert.equal(r.montantFcfa, PRIX);
  assert.equal(await soldeDe('awa'), 5000);
  assert.deepEqual(remboursements, []);
  assert.equal((await db.doc(`commandes/${commandeId}`).get()).get('statut'), 'remboursee');
  await verifierLivre('awa');
});

test('un remboursement n\'est jamais bloqué par le plafond du solde', async () => {
  await db.doc('portefeuilles/awa').set({ soldeFcfa: SOLDE_MAX_FCFA - 1000 });
  await db.doc('commandes/cmd_plafond').set({
    clientId: 'awa', fournisseur: 'portefeuille', prixFcfa: 5000, statut: 'payee', sessionPaiementId: 'wallet_cmd_plafond',
  });
  assert.equal(await rembourserSurPortefeuille(db, db.doc('commandes/cmd_plafond'), 'test', midi), true);
  assert.equal(await soldeDe('awa'), SOLDE_MAX_FCFA - 1000 + 5000); // au-delà du plafond : accepté
});

test('remboursement d\'une commande mobile money : ne touche pas au portefeuille', async () => {
  await db.doc('commandes/cmd_wave').set({ clientId: 'awa', fournisseur: 'simulation', prixFcfa: 2300, statut: 'payee' });
  assert.equal(await rembourserSurPortefeuille(db, db.doc('commandes/cmd_wave'), 'test', midi), false);
  assert.equal((await db.doc('portefeuilles/awa').get()).exists, false);
  assert.equal((await db.doc('commandes/cmd_wave').get()).get('statut'), 'payee');
});

// --- Ajustement Admin ------------------------------------------------------

test('ajustement Admin : crédit, débit, livre et journal', async () => {
  const c = await ajusterPortefeuille(db, 'admin', { clientId: 'awa', montantFcfa: 1500, motif: 'geste commercial' }, midi);
  assert.equal(c.soldeFcfa, 1500);
  const d = await ajusterPortefeuille(db, 'admin', { clientId: 'awa', montantFcfa: -500, motif: 'erreur de saisie' }, midi);
  assert.equal(d.soldeFcfa, 1000);
  assert.equal(await soldeDe('awa'), 1000);
  const m = await mouvements('awa');
  assert.equal(m.length, 2);
  assert.ok(m.every((x) => x.type === 'ajustement_admin' && (x.note ?? '').length > 0));
  const journal = await db.collection('journal_admin').where('action', '==', 'ajustement_portefeuille').get();
  assert.equal(journal.size, 2);
  assert.equal(journal.docs[0].get('adminId'), 'admin');
  await verifierLivre('awa');
});

test('ajustement Admin : réservé à l\'Admin, solde jamais négatif ni au-delà du plafond', async () => {
  const ok = { clientId: 'awa', montantFcfa: 1000, motif: 'test' };
  assert.equal(await code(ajusterPortefeuille(db, undefined, ok, midi)), 'unauthenticated');
  assert.equal(await code(ajusterPortefeuille(db, 'awa', ok, midi)), 'permission-denied');
  assert.equal(await code(ajusterPortefeuille(db, 'moussa', ok, midi)), 'permission-denied');
  assert.equal(await code(ajusterPortefeuille(db, 'admin', { ...ok, montantFcfa: 0 }, midi)), 'invalid-argument');
  assert.equal(await code(ajusterPortefeuille(db, 'admin', { ...ok, montantFcfa: 1.5 }, midi)), 'invalid-argument');
  assert.equal(await code(ajusterPortefeuille(db, 'admin', { ...ok, motif: '  ' }, midi)), 'invalid-argument');
  assert.equal(await code(ajusterPortefeuille(db, 'admin', { ...ok, clientId: 'moussa' }, midi)), 'not-found');
  assert.equal(await code(ajusterPortefeuille(db, 'admin', { ...ok, clientId: 'fantome' }, midi)), 'not-found');
  assert.equal(await code(ajusterPortefeuille(db, 'admin', { ...ok, montantFcfa: -1 }, midi)), 'failed-precondition');
  assert.equal(await code(ajusterPortefeuille(db, 'admin', { ...ok, montantFcfa: SOLDE_MAX_FCFA + 1 }, midi)), 'invalid-argument');
  await adjust('awa', SOLDE_MAX_FCFA);
  assert.equal(await code(ajusterPortefeuille(db, 'admin', ok, midi)), 'failed-precondition');
  assert.equal(await soldeDe('awa'), SOLDE_MAX_FCFA);
  assert.equal((await db.collection('journal_admin').get()).size, 1);
});

// --- Cohérence d'ensemble --------------------------------------------------

test('scénario complet : recharges, courses, annulation, ajustement — le livre reste exact', async () => {
  await recharger('awa', 10_000);
  const a = await payerParSolde('awa');
  await payerParSolde('awa');
  await annulerCourse(db, fournisseur, 'awa', { courseId: a.courseId }, minutes(1));
  await adjust('awa', 300);
  await recharger('awa', 500);
  assert.equal(await soldeDe('awa'), 10_000 - PRIX + 300 + 500);
  await verifierLivre('awa');
  await verifierLivre('fatou');
});
