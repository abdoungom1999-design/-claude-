// Tests de la création de course sur l'émulateur Firestore :
// npm run test:emulateur (lance l'émulateur, puis ces tests).
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { creerCourse as creerCourseCore, idCourse } from '../src/commandes';
import { calculDistance, cleTrajet } from '../src/distances';
import type { ClientGoogle } from '../src/google';

const PLATEAU = { latitude: 14.6928, longitude: -17.4467 };
const ALMADIES = { latitude: 14.7456, longitude: -17.5134 };
const midi = new Date(Date.UTC(2026, 8, 27, 12));
const huitHeures = new Date(Date.UTC(2026, 8, 27, 8));

const commande = (extra: Record<string, unknown> = {}) => ({
  type: 'PASSAGER',
  depart: PLATEAU,
  arrivee: ALMADIES,
  adresseDepart: 'Plateau',
  adresseArrivee: 'Almadies',
  methodePaiement: 'ORANGE_MONEY',
  transactionId: 'TXN-OM-DEMO-42',
  prixAttendu: 2300,
  ...extra,
});

let app: App;
let db: Firestore;

/** Google simulé : 10,2 km par la route ; compte ses appels. */
let appelsRoutes = 0;
const googleFactice = {
  itineraire: async () => {
    appelsRoutes++;
    return { distanceKm: 10.2 };
  },
} as unknown as ClientGoogle;

const creerCourse = (base: Firestore, uid: string | undefined, donnees: unknown, quand: Date) =>
  creerCourseCore(base, calculDistance(base, googleFactice, () => quand), uid, donnees, quand);

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' });
  db = getFirestore(app);
});

after(() => deleteApp(app));

beforeEach(async () => {
  appelsRoutes = 0;
  for (const nom of ['users', 'courses', 'distances']) {
    const docs = await db.collection(nom).listDocuments();
    await Promise.all(docs.map((d) => d.delete()));
  }
  await db.doc('users/awa').set({ role: 'client', nom: 'Awa' });
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

test('course créée par le serveur, avec le prix du serveur', async () => {
  const resultat = await creerCourse(db, 'awa', commande(), midi);
  assert.deepEqual(resultat, { courseId: idCourse('awa', 'TXN-OM-DEMO-42'), prixFcfa: 2300 });

  const course = (await db.doc(`courses/${resultat.courseId}`).get()).data()!;
  assert.equal(course.clientId, 'awa');
  assert.equal(course.chauffeurId, null);
  assert.equal(course.statut, 'en_attente');
  assert.equal(course.prixFcfa, 2300);
  assert.equal(course.methodePaiement, 'ORANGE_MONEY');
  assert.equal(course.modePaiement, 'test');
  assert.equal(course.latitudeArrivee, ALMADIES.latitude);
  assert.equal(course.distanceKm, 10.2);
  assert.equal(course.sourceDistance, 'route');
  assert.ok(course.timestamp instanceof Timestamp);
});

test('prix vu par le client différent (tranche horaire changée) : rien n\'est créé, nouveau prix renvoyé', async () => {
  const erreur = await refuse(creerCourse(db, 'awa', commande(), huitHeures), 'failed-precondition');
  assert.deepEqual(erreur.details, { raison: 'prix-modifie', prixFcfa: 2800 });
  assert.equal((await db.collection('courses').get()).size, 0);
});

test('prix trafiqué à la baisse par le client : refusé', async () => {
  await refuse(creerCourse(db, 'awa', commande({ prixAttendu: 100 }), midi), 'failed-precondition');
  assert.equal((await db.collection('courses').get()).size, 0);
});

test('même commande envoyée deux fois : une seule course', async () => {
  const [a, b] = await Promise.all([
    creerCourse(db, 'awa', commande(), midi),
    creerCourse(db, 'awa', commande(), midi),
  ]);
  assert.equal(a.courseId, b.courseId);
  assert.equal((await db.collection('courses').get()).size, 1);
});

test('non connecté, sans profil ou compte banni : refusé', async () => {
  await refuse(creerCourse(db, undefined, commande(), midi), 'unauthenticated');
  await refuse(creerCourse(db, 'inconnu', commande(), midi), 'permission-denied');
  await refuse(creerCourse(db, 'banni', commande(), midi), 'permission-denied');
  assert.equal((await db.collection('courses').get()).size, 0);
});

test('distance par la route mise en cache : Google appelé une seule fois par trajet', async () => {
  await creerCourse(db, 'awa', commande({ transactionId: 'TXN-1' }), midi);
  await creerCourse(db, 'awa', commande({ transactionId: 'TXN-2' }), midi);
  assert.equal(appelsRoutes, 1);
  const cache = await db.doc(`distances/${cleTrajet(PLATEAU, ALMADIES)}`).get();
  assert.equal(cache.get('distanceKm'), 10.2);
});

test('cache périmé (plus de 30 jours) : distance recalculée', async () => {
  await creerCourse(db, 'awa', commande({ transactionId: 'TXN-1' }), midi);
  const plusTard = new Date(midi.getTime() + 31 * 24 * 3600 * 1000);
  await creerCourse(db, 'awa', commande({ transactionId: 'TXN-2' }), plusTard);
  assert.equal(appelsRoutes, 2);
});

test('Google en panne : la commande passe au prix estimé (vol d\'oiseau x 1,1), sans cache', async () => {
  const enPanne = { itineraire: async () => { throw new Error('503'); } } as unknown as ClientGoogle;
  const resultat = await creerCourseCore(db, calculDistance(db, enPanne, () => midi), 'awa', commande(), midi);
  assert.equal(resultat.prixFcfa, 2300);
  const course = (await db.doc(`courses/${resultat.courseId}`).get()).data()!;
  assert.equal(course.sourceDistance, 'estimation');
  assert.equal((await db.doc(`distances/${cleTrajet(PLATEAU, ALMADIES)}`).get()).exists, false);
});
