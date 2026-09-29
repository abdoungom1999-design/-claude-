// Tests des actions Admin (remboursement, sanction) sur l'émulateur
// Firestore : npm run test:emulateur.
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { rembourserCourseAdmin, sanctionnerCompte } from '../src/admin';
import { FournisseurSimule } from '../src/fournisseurs';

const maintenant = new Date(Date.UTC(2026, 8, 29, 12));

let app: App;
let db: Firestore;
let remboursements: string[];
let fournisseur: FournisseurSimule;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' }, 'admin');
  db = getFirestore(app);
});

after(() => deleteApp(app));

/** Course payée par le serveur (commande "payee"), dans l'état voulu. */
async function course(id: string, statut: string, extra: Record<string, unknown> = {}) {
  await db.doc(`commandes/k-${id}`).set({
    clientId: 'awa', statut: 'payee', prixFcfa: 2300, fournisseur: 'simulation', sessionPaiementId: `sim_${id}`,
  });
  await db.doc(`courses/${id}`).set({
    clientId: 'awa', chauffeurId: 'moussa', statut, prixFcfa: 2300, commandeId: `k-${id}`, ...extra,
  });
}

beforeEach(async () => {
  remboursements = [];
  fournisseur = new FournisseurSimule('secret', 'https://page', remboursements);
  for (const nom of ['users', 'courses', 'commandes', 'tickets', 'journal_admin', 'profils_publics', 'positions_chauffeurs']) {
    const docs = await db.collection(nom).listDocuments();
    await Promise.all(docs.map((d) => db.recursiveDelete(d)));
  }
  await db.doc('users/chef').set({ role: 'admin' });
  await db.doc('users/chef2').set({ role: 'admin' });
  await db.doc('users/awa').set({ role: 'client' });
  await db.doc('users/moussa').set({ role: 'conducteur', statutValidation: 'valide' });
  await db.doc('profils_publics/moussa').set({ nom: 'Moussa', disponible: true });
  await db.doc('positions_chauffeurs/moussa').set({ latitude: 14.7, longitude: -17.4 });
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

const journal = async () => (await db.collection('journal_admin').get()).docs.map((d) => d.data());

// --- Remboursement ------------------------------------------------------

test('remboursement intégral d\'une course terminée : commande remboursée, part du chauffeur retirée, trace dans le journal', async () => {
  await course('c1', 'terminee', { commissionFcfa: 345 });
  const r = await rembourserCourseAdmin(db, fournisseur, 'chef', { courseId: 'c1', motif: 'Chauffeur désagréable' }, maintenant);
  assert.deepEqual(r, { rembourse: true, montantFcfa: 2300, partChauffeurRetireeFcfa: 1955 });
  assert.deepEqual(remboursements, ['sim_c1']);
  assert.equal((await db.doc('commandes/k-c1').get()).get('statut'), 'remboursee');
  const c = (await db.doc('courses/c1').get()).data()!;
  assert.equal(c.rembourseePar, 'chef');
  assert.ok(c.rembourseeLe instanceof Timestamp);
  assert.equal(c.partChauffeurRetireeFcfa, 1955);
  const [entree] = await journal();
  assert.equal(entree.action, 'remboursement');
  assert.equal(entree.adminId, 'chef');
  assert.equal(entree.courseId, 'c1');
  assert.equal(entree.montantFcfa, 2300);
  assert.equal(entree.resultat, 'rembourse');
  assert.equal(entree.motif, 'Chauffeur désagréable');
  assert.equal(entree.chauffeurId, 'moussa');
  assert.equal(entree.partChauffeurRetireeFcfa, 1955);
});

test('part du chauffeur : même formule sans commission figée, rien sur une course annulée', async () => {
  await course('c1', 'terminee');
  const r1 = await rembourserCourseAdmin(db, fournisseur, 'chef', { courseId: 'c1', motif: 'x' }, maintenant);
  assert.equal(r1.partChauffeurRetireeFcfa, 1955);
  await course('c2', 'annulee');
  const r2 = await rembourserCourseAdmin(db, fournisseur, 'chef', { courseId: 'c2', motif: 'x' }, maintenant);
  assert.deepEqual(r2, { rembourse: true, montantFcfa: 2300, partChauffeurRetireeFcfa: 0 });
});

test('remboursement : le client est prévenu dans son ticket', async () => {
  await course('c1', 'terminee');
  await db.doc('tickets/c1').set({ clientId: 'awa', statut: 'ouvert', nonLuClient: false });
  await rembourserCourseAdmin(db, fournisseur, 'chef', { courseId: 'c1', motif: 'Geste commercial' }, maintenant);
  const messages = (await db.collection('tickets/c1/messages').get()).docs.map((d) => d.data());
  assert.equal(messages.length, 1);
  assert.equal(messages[0].auteurRole, 'systeme');
  assert.match(messages[0].texte, /remboursée intégralement \(2300 FCFA\)/);
  assert.equal((await db.doc('tickets/c1').get()).get('nonLuClient'), true);
});

test('remboursement refusé : déjà remboursée, course en cours, sans paiement serveur, motif absent', async () => {
  await course('c1', 'terminee');
  await rembourserCourseAdmin(db, fournisseur, 'chef', { courseId: 'c1', motif: 'x' }, maintenant);
  await refuse(rembourserCourseAdmin(db, fournisseur, 'chef', { courseId: 'c1', motif: 'x' }, maintenant), 'already-exists');

  await course('c2', 'en_cours');
  await refuse(rembourserCourseAdmin(db, fournisseur, 'chef', { courseId: 'c2', motif: 'x' }, maintenant), 'failed-precondition');

  await db.doc('courses/ancienne').set({ clientId: 'awa', statut: 'terminee', prixFcfa: 2000 });
  await refuse(rembourserCourseAdmin(db, fournisseur, 'chef', { courseId: 'ancienne', motif: 'x' }, maintenant), 'failed-precondition');

  await course('c3', 'terminee');
  await refuse(rembourserCourseAdmin(db, fournisseur, 'chef', { courseId: 'c3' }, maintenant), 'invalid-argument');
  await refuse(rembourserCourseAdmin(db, fournisseur, 'chef', { courseId: 'inexistante', motif: 'x' }, maintenant), 'not-found');
  assert.equal(remboursements.length, 1);
});

test('fournisseur en panne : échec visible et tracé, puis nouvel essai réussi', async () => {
  await course('c1', 'terminee');
  const rembourser = fournisseur.rembourser.bind(fournisseur);
  fournisseur.rembourser = async () => { throw new Error('Wave 500'); };
  const r = await rembourserCourseAdmin(db, fournisseur, 'chef', { courseId: 'c1', motif: 'x' }, maintenant);
  assert.equal(r.rembourse, false);
  // Client pas remboursé : le chauffeur garde sa part.
  assert.equal(r.partChauffeurRetireeFcfa, 0);
  assert.equal((await db.doc('courses/c1').get()).get('rembourseeLe'), undefined);
  assert.equal((await db.doc('commandes/k-c1').get()).get('statut'), 'remboursement_echoue');
  assert.equal((await journal())[0].resultat, 'echec_fournisseur');

  fournisseur.rembourser = rembourser;
  const r2 = await rembourserCourseAdmin(db, fournisseur, 'chef', { courseId: 'c1', motif: 'x' }, maintenant);
  assert.equal(r2.rembourse, true);
  assert.equal(r2.partChauffeurRetireeFcfa, 1955);
  assert.equal((await db.doc('commandes/k-c1').get()).get('statut'), 'remboursee');
});

test('actions Admin interdites à un client, un chauffeur ou un anonyme', async () => {
  await course('c1', 'terminee');
  for (const uid of ['awa', 'moussa', 'inconnu']) {
    await refuse(rembourserCourseAdmin(db, fournisseur, uid, { courseId: 'c1', motif: 'x' }, maintenant), 'permission-denied');
    await refuse(sanctionnerCompte(db, fournisseur, uid, { uid: 'moussa', statutCompte: 'suspendu', motif: 'x' }, maintenant), 'permission-denied');
  }
  await refuse(rembourserCourseAdmin(db, fournisseur, undefined, { courseId: 'c1', motif: 'x' }, maintenant), 'unauthenticated');
  assert.equal(remboursements.length, 0);
  assert.equal((await db.doc('users/moussa').get()).get('statutCompte'), undefined);
});

// --- Sanction ----------------------------------------------------------

test('suspendre un chauffeur en pleine course : course annulée, client remboursé, chauffeur retiré de la carte', async () => {
  await course('active', 'en_cours');
  await course('finie', 'terminee');
  const r = await sanctionnerCompte(db, fournisseur, 'chef', { uid: 'moussa', statutCompte: 'suspendu', motif: 'Plainte client' }, maintenant);
  assert.deepEqual(r, { statutCompte: 'suspendu', coursesAnnulees: 1, remboursements: 1 });

  const compte = (await db.doc('users/moussa').get()).data()!;
  assert.equal(compte.statutCompte, 'suspendu');
  assert.equal(compte.motifSanction, 'Plainte client');
  assert.equal(compte.sanctionnePar, 'chef');

  const active = (await db.doc('courses/active').get()).data()!;
  assert.equal(active.statut, 'annulee');
  assert.equal(active.annuleePar, 'systeme');
  assert.equal(active.motifAnnulation, 'chauffeur_suspendu');
  assert.equal((await db.doc('commandes/k-active').get()).get('statut'), 'remboursee');
  assert.equal((await db.doc('courses/finie').get()).get('statut'), 'terminee');
  assert.equal((await db.doc('commandes/k-finie').get()).get('statut'), 'payee');

  assert.equal((await db.doc('positions_chauffeurs/moussa').get()).exists, false);
  assert.equal((await db.doc('profils_publics/moussa').get()).get('disponible'), false);
  const [entree] = await journal();
  assert.equal(entree.action, 'sanction');
  assert.equal(entree.cible, 'moussa');
  assert.equal(entree.coursesAnnulees, 1);
});

test('réactivation : sans motif, le chauffeur validé redevient disponible', async () => {
  await sanctionnerCompte(db, fournisseur, 'chef', { uid: 'moussa', statutCompte: 'banni', motif: 'Fraude' }, maintenant);
  const r = await sanctionnerCompte(db, fournisseur, 'chef', { uid: 'moussa', statutCompte: 'actif' }, maintenant);
  assert.equal(r.statutCompte, 'actif');
  const compte = (await db.doc('users/moussa').get()).data()!;
  assert.equal(compte.statutCompte, 'actif');
  assert.equal(compte.motifSanction, undefined);
  assert.equal((await db.doc('profils_publics/moussa').get()).get('disponible'), true);
});

test('sanction refusée : sans motif, statut inconnu, soi-même, un autre Admin, compte inconnu', async () => {
  await refuse(sanctionnerCompte(db, fournisseur, 'chef', { uid: 'moussa', statutCompte: 'suspendu' }, maintenant), 'invalid-argument');
  await refuse(sanctionnerCompte(db, fournisseur, 'chef', { uid: 'moussa', statutCompte: 'exile', motif: 'x' }, maintenant), 'invalid-argument');
  await refuse(sanctionnerCompte(db, fournisseur, 'chef', { uid: 'chef', statutCompte: 'suspendu', motif: 'x' }, maintenant), 'failed-precondition');
  await refuse(sanctionnerCompte(db, fournisseur, 'chef', { uid: 'chef2', statutCompte: 'banni', motif: 'x' }, maintenant), 'permission-denied');
  await refuse(sanctionnerCompte(db, fournisseur, 'chef', { uid: 'fantome', statutCompte: 'suspendu', motif: 'x' }, maintenant), 'not-found');
  assert.equal((await journal()).length, 0);
});

test('suspendre un client : compte bloqué, rien d\'autre à annuler', async () => {
  const r = await sanctionnerCompte(db, fournisseur, 'chef', { uid: 'awa', statutCompte: 'suspendu', motif: 'Abus' }, maintenant);
  assert.deepEqual(r, { statutCompte: 'suspendu', coursesAnnulees: 0, remboursements: 0 });
  assert.equal((await db.doc('users/awa').get()).get('statutCompte'), 'suspendu');
});
