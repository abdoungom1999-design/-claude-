// Tests du parcours de paiement sur l'émulateur Firestore :
// npm run test:emulateur (lance l'émulateur, puis ces tests).
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { calculDistance, cleTrajet } from '../src/distances';
import { FournisseurSimule, type EvenementPaiement } from '../src/fournisseurs';
import type { ClientGoogle } from '../src/google';
import {
  annulerCourse,
  creerPaiement as creerPaiementCore,
  surveiller,
  traiterEvenement,
} from '../src/paiements';
import { secretSimulation } from '../src/simulation';

const PLATEAU = { latitude: 14.6928, longitude: -17.4467 };
const ALMADIES = { latitude: 14.7456, longitude: -17.5134 };
const midi = new Date(Date.UTC(2026, 8, 27, 12));
const huitHeures = new Date(Date.UTC(2026, 8, 27, 8));
const minutes = (n: number) => new Date(midi.getTime() + n * 60 * 1000);

const demande = (extra: Record<string, unknown> = {}) => ({
  type: 'PASSAGER',
  depart: PLATEAU,
  arrivee: ALMADIES,
  adresseDepart: 'Plateau',
  adresseArrivee: 'Almadies',
  methodePaiement: 'WAVE',
  prixAttendu: 2300,
  ...extra,
});

let app: App;
let db: Firestore;
let remboursements: string[];
let fournisseur: FournisseurSimule;

/** Google simulé : 10,2 km par la route ; compte ses appels. */
let appelsRoutes = 0;
const googleFactice = {
  itineraire: async () => {
    appelsRoutes++;
    return { distanceKm: 10.2 };
  },
} as unknown as ClientGoogle;

const creerPaiement = (uid: string | undefined, donnees: unknown, quand = midi, google = googleFactice) =>
  creerPaiementCore(db, calculDistance(db, google, () => quand), fournisseur, uid, donnees, quand);

/** Événement tel que le fournisseur le confirmerait pour cette commande. */
async function evenement(commandeId: string, extra: Partial<EvenementPaiement> = {}): Promise<EvenementPaiement> {
  const c = (await db.doc(`commandes/${commandeId}`).get()).data()!;
  return { sessionId: c.sessionPaiementId, commandeId, reussi: true, montantFcfa: c.prixFcfa, devise: 'XOF', ...extra };
}

async function payer(uid = 'awa', quand = midi): Promise<{ commandeId: string; courseId: string }> {
  const { commandeId } = await creerPaiement(uid, demande(), quand);
  assert.equal(await traiterEvenement(db, fournisseur, await evenement(commandeId), quand), 'course_creee');
  const courseId = (await db.doc(`commandes/${commandeId}`).get()).get('courseId') as string;
  return { commandeId, courseId };
}

const statutCommande = async (id: string) => (await db.doc(`commandes/${id}`).get()).get('statut');
const course = async (id: string) => (await db.doc(`courses/${id}`).get()).data()!;
const nombre = async (collection: string) => (await db.collection(collection).get()).size;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' });
  db = getFirestore(app);
});

after(() => deleteApp(app));

beforeEach(async () => {
  appelsRoutes = 0;
  remboursements = [];
  fournisseur = new FournisseurSimule('secret', 'https://page', remboursements);
  for (const nom of ['users', 'courses', 'commandes', 'distances', 'config']) {
    const docs = await db.collection(nom).listDocuments();
    await Promise.all(docs.map((d) => d.delete()));
  }
  await db.doc('users/awa').set({ role: 'client', nom: 'Awa' });
  await db.doc('users/fatou').set({ role: 'client', nom: 'Fatou' });
  await db.doc('users/moussa').set({ role: 'conducteur', statutValidation: 'valide' });
  await db.doc('users/banni').set({ role: 'client', statutCompte: 'banni' });
});

async function refuse(promesse: Promise<unknown>, code: string): Promise<HttpsError> {
  try {
    await promesse;
  } catch (e) {
    assert.ok(e instanceof HttpsError, String(e));
    assert.equal(e.code, code);
    return e;
  }
  assert.fail(`aurait dû être refusé (${code})`);
}

// --- Demande de paiement -------------------------------------------------

test('demande de paiement : commande en attente au prix du serveur, aucune course', async () => {
  const r = await creerPaiement('awa', demande());
  assert.equal(r.prixFcfa, 2300);
  assert.match(r.lienPaiement!, /^https:\/\/page\?session=sim_/);

  const c = (await db.doc(`commandes/${r.commandeId}`).get()).data()!;
  assert.equal(c.clientId, 'awa');
  assert.equal(c.statut, 'en_attente_paiement');
  assert.equal(c.prixFcfa, 2300);
  assert.equal(c.fournisseur, 'simulation');
  assert.equal(c.lienPaiement, r.lienPaiement);
  assert.equal(c.distanceKm, 10.2);
  assert.equal(c.sourceDistance, 'route');
  assert.equal((c.expireLe as Timestamp).toMillis(), minutes(20).getTime());
  assert.equal(await nombre('courses'), 0);
});

test('prix vu par le client différent (tranche horaire changée) : rien n\'est créé, nouveau prix renvoyé', async () => {
  const erreur = await refuse(creerPaiement('awa', demande(), huitHeures), 'failed-precondition');
  assert.deepEqual(erreur.details, { raison: 'prix-modifie', prixFcfa: 2800 });
  await refuse(creerPaiement('awa', demande({ prixAttendu: 100 })), 'failed-precondition');
  assert.equal(await nombre('commandes'), 0);
});

test('non connecté, sans profil ou compte banni : refusé', async () => {
  await refuse(creerPaiement(undefined, demande()), 'unauthenticated');
  // Connexion vérifiée avant le contenu (contrôle de la CI : requête vide).
  await refuse(creerPaiement(undefined, {}), 'unauthenticated');
  await refuse(creerPaiement('inconnu', demande()), 'permission-denied');
  await refuse(creerPaiement('banni', demande()), 'permission-denied');
  assert.equal(await nombre('commandes'), 0);
});

test('fournisseur indisponible : erreur claire, aucune commande', async () => {
  fournisseur.creerSession = async () => { throw new Error('Wave 503'); };
  await refuse(creerPaiement('awa', demande()), 'unavailable');
  assert.equal(await nombre('commandes'), 0);
});

test('distance par la route mise en cache ; cache périmé recalculé ; Google en panne : secours', async () => {
  await creerPaiement('awa', demande());
  await creerPaiement('awa', demande());
  assert.equal(appelsRoutes, 1);
  assert.equal((await db.doc(`distances/${cleTrajet(PLATEAU, ALMADIES)}`).get()).get('distanceKm'), 10.2);

  const plusTard = new Date(midi.getTime() + 31 * 24 * 3600 * 1000);
  await creerPaiement('awa', demande(), plusTard);
  assert.equal(appelsRoutes, 2);

  await db.doc(`distances/${cleTrajet(PLATEAU, ALMADIES)}`).delete();
  const enPanne = { itineraire: async () => { throw new Error('503'); } } as unknown as ClientGoogle;
  const r = await creerPaiement('awa', demande(), midi, enPanne);
  assert.equal(r.prixFcfa, 2300);
  assert.equal((await db.doc(`commandes/${r.commandeId}`).get()).get('sourceDistance'), 'estimation');
});

// --- Confirmation du fournisseur ----------------------------------------

test('paiement confirmé : course en attente créée pour les chauffeurs, commande payée', async () => {
  const { commandeId, courseId } = await payer();
  const c = await course(courseId);
  assert.equal(c.clientId, 'awa');
  assert.equal(c.chauffeurId, null);
  assert.equal(c.statut, 'en_attente');
  assert.equal(c.prixFcfa, 2300);
  assert.equal(c.methodePaiement, 'WAVE');
  assert.equal(c.modePaiement, 'simulation');
  assert.equal(c.commandeId, commandeId);
  assert.equal(c.latitudeArrivee, ALMADIES.latitude);
  assert.ok(c.timestamp instanceof Timestamp);
  assert.equal(await statutCommande(commandeId), 'payee');
});

test('même confirmation reçue plusieurs fois (même simultanément) : une seule course', async () => {
  const { commandeId } = await creerPaiement('awa', demande());
  const e = await evenement(commandeId);
  const resultats = await Promise.all([1, 2, 3].map(() => traiterEvenement(db, fournisseur, e, midi)));
  assert.deepEqual(resultats.sort(), ['course_creee', 'deja_traite', 'deja_traite']);
  assert.equal(await nombre('courses'), 1);
});

test('paiement refusé : commande échouée, aucune course', async () => {
  const { commandeId } = await creerPaiement('awa', demande());
  assert.equal(await traiterEvenement(db, fournisseur, await evenement(commandeId, { reussi: false }), midi), 'echec_enregistre');
  assert.equal(await statutCommande(commandeId), 'echouee');
  assert.equal(await nombre('courses'), 0);
});

test('montant ou devise différents du prix : anomalie, aucune course', async () => {
  const a = await creerPaiement('awa', demande());
  assert.equal(await traiterEvenement(db, fournisseur, await evenement(a.commandeId, { montantFcfa: 100 }), midi), 'anomalie');
  const b = await creerPaiement('awa', demande());
  assert.equal(await traiterEvenement(db, fournisseur, await evenement(b.commandeId, { devise: 'EUR' }), midi), 'anomalie');
  assert.equal(await statutCommande(a.commandeId), 'anomalie');
  assert.equal(await nombre('courses'), 0);
});

test('commande inconnue ou session d\'une autre commande : ignorée', async () => {
  const { commandeId } = await creerPaiement('awa', demande());
  const e = await evenement(commandeId);
  assert.equal(await traiterEvenement(db, fournisseur, { ...e, commandeId: 'inexistante' }, midi), 'inconnue');
  assert.equal(await traiterEvenement(db, fournisseur, { ...e, sessionId: 'sim_autre' }, midi), 'inconnue');
  assert.equal(await statutCommande(commandeId), 'en_attente_paiement');
});

test('paiement arrivé après expiration : remboursé, aucune course', async () => {
  const { commandeId } = await creerPaiement('awa', demande());
  assert.deepEqual(await surveiller(db, fournisseur, minutes(21)), { expirees: 1, sansChauffeur: 0 });
  assert.equal(await statutCommande(commandeId), 'expiree');

  assert.equal(await traiterEvenement(db, fournisseur, await evenement(commandeId), minutes(22)), 'rembourse');
  assert.equal(await statutCommande(commandeId), 'remboursee');
  assert.equal(remboursements.length, 1);
  assert.equal(await nombre('courses'), 0);
});

// --- Annulations et remboursements --------------------------------------

test('le client annule sa demande en attente : course annulée et remboursée', async () => {
  const { commandeId, courseId } = await payer();
  assert.deepEqual(await annulerCourse(db, fournisseur, 'awa', { courseId }, minutes(2)), { rembourse: true });
  const c = await course(courseId);
  assert.equal(c.statut, 'annulee');
  assert.equal(c.annuleePar, 'client');
  const commande = (await db.doc(`commandes/${commandeId}`).get()).data()!;
  assert.equal(commande.statut, 'remboursee');
  assert.equal(commande.motifRemboursement, 'course_annulee');
  assert.equal(remboursements.length, 1);
});

test('le client ne peut plus annuler une fois la course acceptée ; un tiers jamais', async () => {
  const { courseId } = await payer();
  await refuse(annulerCourse(db, fournisseur, 'fatou', { courseId }, midi), 'permission-denied');
  await refuse(annulerCourse(db, fournisseur, undefined, { courseId }, midi), 'unauthenticated');
  await refuse(annulerCourse(db, fournisseur, 'awa', { courseId: '../x' }, midi), 'invalid-argument');
  await refuse(annulerCourse(db, fournisseur, 'awa', { courseId: 'inexistante' }, midi), 'not-found');

  await db.doc(`courses/${courseId}`).update({ statut: 'acceptee', chauffeurId: 'moussa' });
  await refuse(annulerCourse(db, fournisseur, 'awa', { courseId }, midi), 'failed-precondition');
  assert.equal(remboursements.length, 0);
});

test('le chauffeur attribué annule avec un motif : client remboursé', async () => {
  const { courseId } = await payer();
  await db.doc(`courses/${courseId}`).update({ statut: 'en_cours', chauffeurId: 'moussa' });
  await refuse(annulerCourse(db, fournisseur, 'moussa', { courseId, motif: 'fatigue' }, midi), 'invalid-argument');
  assert.deepEqual(await annulerCourse(db, fournisseur, 'moussa', { courseId, motif: 'panne' }, midi), { rembourse: true });
  const c = await course(courseId);
  assert.equal(c.annuleePar, 'chauffeur');
  assert.equal(c.motifAnnulation, 'panne');
  await refuse(annulerCourse(db, fournisseur, 'moussa', { courseId, motif: 'panne' }, midi), 'failed-precondition');
  assert.equal(remboursements.length, 1);
});

test('remboursement refusé par le fournisseur : commande signalée, jamais silencieuse', async () => {
  const { commandeId, courseId } = await payer();
  fournisseur.rembourser = async () => { throw new Error('Wave 500'); };
  assert.deepEqual(await annulerCourse(db, fournisseur, 'awa', { courseId }, midi), { rembourse: false });
  assert.equal(await statutCommande(commandeId), 'remboursement_echoue');
  assert.equal((await course(courseId)).statut, 'annulee');
});

// --- Surveillance --------------------------------------------------------

test('surveillance : paiement non finalisé expiré au bout de 20 minutes', async () => {
  const { commandeId } = await creerPaiement('awa', demande());
  assert.deepEqual(await surveiller(db, fournisseur, minutes(19)), { expirees: 0, sansChauffeur: 0 });
  assert.deepEqual(await surveiller(db, fournisseur, minutes(21)), { expirees: 1, sansChauffeur: 0 });
  assert.equal(await statutCommande(commandeId), 'expiree');
  assert.deepEqual(await surveiller(db, fournisseur, minutes(30)), { expirees: 0, sansChauffeur: 0 });
});

test('surveillance : course sans chauffeur au bout de 10 minutes annulée et remboursée', async () => {
  const { commandeId, courseId } = await payer();
  const creeLe = ((await course(courseId)).timestamp as Timestamp).toDate();
  const apres = (n: number) => new Date(creeLe.getTime() + n * 60 * 1000);

  const acceptee = await payer('fatou');
  await db.doc(`courses/${acceptee.courseId}`).update({ statut: 'acceptee', chauffeurId: 'moussa' });

  assert.deepEqual(await surveiller(db, fournisseur, apres(9)), { expirees: 0, sansChauffeur: 0 });
  assert.deepEqual(await surveiller(db, fournisseur, apres(11)), { expirees: 0, sansChauffeur: 1 });
  const c = await course(courseId);
  assert.equal(c.statut, 'annulee');
  assert.equal(c.annuleePar, 'systeme');
  assert.equal(c.motifAnnulation, 'aucun_chauffeur');
  assert.equal(await statutCommande(commandeId), 'remboursee');
  assert.equal((await course(acceptee.courseId)).statut, 'acceptee');
  assert.equal(remboursements.length, 1);
});

// --- Secret de la simulation --------------------------------------------

test('secret de la simulation : créé une fois, puis toujours le même', async () => {
  const [a, b] = await Promise.all([secretSimulation(db), secretSimulation(db)]);
  assert.equal(a, b);
  assert.match(a, /^[0-9a-f]{64}$/);
  assert.equal(await secretSimulation(db), a);
});
