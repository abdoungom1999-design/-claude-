// Itinéraire du chauffeur sur l'émulateur Firestore : npm run test:emulateur.
// Google est remplacé par un faux `fetch` qui enregistre la requête.
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { ClientGoogle } from '../src/google';
import { DISTANCE_ARRIVEE_M, INTERVALLE_MIN_MS, itineraireCourse } from '../src/itineraire';
import { departExactDe } from '../src/paiements';
import { arrondirPosition } from '../src/proximite';

const midi = new Date(Date.UTC(2026, 9, 9, 12));
const apres = (ms: number) => new Date(midi.getTime() + ms);

// Le client attend au Plateau, il va aux Almadies ; le chauffeur est à la Médina.
const client = { latitude: 14.6928, longitude: -17.4467 };
const destination = { latitude: 14.745, longitude: -17.517 };
const chauffeurPosition = { latitude: 14.6781, longitude: -17.4458 };

let app: App;
let db: Firestore;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' }, 'itineraire');
  db = getFirestore(app);
});
after(() => deleteApp(app));
beforeEach(() => db.recursiveDelete(db.collection('courses')));

interface Appel {
  corps: { origin: { location: { latLng: unknown } }; destination: { location: { latLng: unknown } } };
}

/** Google simulé : répond [reponse] (ou [statut] d'erreur) et note chaque requête. */
function googleFactice(reponse: unknown = { routes: [{ distanceMeters: 2650, polyline: { encodedPolyline: 'trace-encodee' } }] }, statut = 200) {
  const appels: Appel[] = [];
  const f = (async (_url: string, init: RequestInit) => {
    appels.push({ corps: JSON.parse(init.body as string) });
    return new Response(JSON.stringify(reponse), { status: statut });
  }) as unknown as typeof fetch;
  return { google: new ClientGoogle('CLE', f), appels };
}

const course = (id: string, extra: Record<string, unknown> = {}) =>
  db.doc(`courses/${id}`).set({
    clientId: 'awa',
    chauffeurId: 'moussa',
    statut: 'acceptee',
    latitudeDepart: client.latitude,
    longitudeDepart: client.longitude,
    latitudeArrivee: destination.latitude,
    longitudeArrivee: destination.longitude,
    ...extra,
  });

/**
 * Course telle que le serveur la crée aujourd'hui : départ arrondi dans la
 * course, position exacte du client dans son document privé (sauf [exact] nul).
 */
async function courseMasquee(id: string, extra: Record<string, unknown> = {}, exact: unknown = client) {
  const arrondi = arrondirPosition(client.latitude, client.longitude);
  await course(id, { latitudeDepart: arrondi.latitude, longitudeDepart: arrondi.longitude, departArrondi: true, ...extra });
  if (exact) await departExactDe(db.doc(`courses/${id}`)).set(exact as Record<string, unknown>);
}

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

const demande = (extra: Record<string, unknown> = {}) => ({ courseId: 'c1', depuis: chauffeurPosition, ...extra });

test('course acceptée : l\'itinéraire mène au client, point lu dans la course (jamais envoyé par l\'app)', async () => {
  await course('c1');
  const { google, appels } = googleFactice();

  const r = await itineraireCourse(db, google, 'moussa', demande({ vers: { latitude: 0, longitude: 0 } }), midi);

  assert.deepEqual(r, { vers: 'client', distanceM: 2650, trace: 'trace-encodee' });
  assert.equal(appels.length, 1);
  assert.deepEqual(appels[0].corps.origin.location.latLng, chauffeurPosition);
  assert.deepEqual(appels[0].corps.destination.location.latLng, client);
  const enregistre = await db.doc('courses/c1').get();
  assert.equal((enregistre.get('itineraireLe') as Timestamp).toMillis(), midi.getTime());
});

test('client à bord : l\'itinéraire mène à la destination', async () => {
  await course('c1', { statut: 'en_cours' });
  const { google, appels } = googleFactice();

  const r = await itineraireCourse(db, google, 'moussa', demande(), midi);

  assert.equal(r.vers, 'destination');
  assert.deepEqual(appels[0].corps.destination.location.latLng, destination);
});

test('au plus un calcul toutes les 10 secondes pour une même course', async () => {
  await course('c1');
  const { google, appels } = googleFactice();
  await itineraireCourse(db, google, 'moussa', demande(), midi);

  await refuse(itineraireCourse(db, google, 'moussa', demande(), apres(INTERVALLE_MIN_MS - 1000)), 'resource-exhausted');
  assert.equal(appels.length, 1, 'le refus ne coûte aucun appel à Google');

  await itineraireCourse(db, google, 'moussa', demande(), apres(INTERVALLE_MIN_MS));
  assert.equal(appels.length, 2);
});

test('seul le chauffeur attribué obtient l\'itinéraire de sa course en cours', async () => {
  await course('c1');
  await course('libre', { chauffeurId: null, statut: 'en_attente' });
  await course('finie', { statut: 'terminee' });
  const { google, appels } = googleFactice();

  await refuse(itineraireCourse(db, google, undefined, demande(), midi), 'unauthenticated');
  await refuse(itineraireCourse(db, google, 'awa', demande(), midi), 'permission-denied'); // le client
  await refuse(itineraireCourse(db, google, 'intrus', demande(), midi), 'permission-denied');
  await refuse(itineraireCourse(db, google, 'moussa', demande({ courseId: 'libre' }), midi), 'permission-denied');
  await refuse(itineraireCourse(db, google, 'moussa', demande({ courseId: 'finie' }), midi), 'failed-precondition');
  await refuse(itineraireCourse(db, google, 'moussa', demande({ courseId: 'absente' }), midi), 'not-found');
  assert.equal(appels.length, 0, 'aucun refus ne coûte un appel à Google');
});

test('requête mal formée ou position absurde : refusée', async () => {
  await course('c1');
  const { google } = googleFactice();
  const essai = (extra: Record<string, unknown>) => itineraireCourse(db, google, 'moussa', demande(extra), midi);

  await refuse(essai({ courseId: 'a/b' }), 'invalid-argument');
  await refuse(essai({ courseId: 12 }), 'invalid-argument');
  await refuse(essai({ depuis: undefined }), 'invalid-argument');
  await refuse(essai({ depuis: { latitude: 'x', longitude: 1 } }), 'invalid-argument');
  await refuse(essai({ depuis: { latitude: 91, longitude: 0 } }), 'invalid-argument');
  await refuse(essai({ depuis: { latitude: NaN, longitude: 0 } }), 'invalid-argument');
  await refuse(essai({ depuis: { latitude: 48.85, longitude: 2.35 } }), 'invalid-argument'); // Paris : hors zone
  await refuse(itineraireCourse(db, google, 'moussa', undefined, midi), 'invalid-argument');
});

test('course sans coordonnées (ancienne course) : refusée proprement', async () => {
  await course('c1', { latitudeDepart: null, longitudeDepart: null });
  const { google } = googleFactice();
  await refuse(itineraireCourse(db, google, 'moussa', demande(), midi), 'failed-precondition');
});

test('chauffeur arrivé (moins de 30 m) : distance sans tracé, aucun appel à Google', async () => {
  await course('c1');
  const { google, appels } = googleFactice();
  const aCoteDuClient = { latitude: client.latitude + 0.0001, longitude: client.longitude }; // ~11 m

  const r = await itineraireCourse(db, google, 'moussa', demande({ depuis: aCoteDuClient }), midi);

  assert.equal(r.vers, 'client');
  assert.equal(r.trace, '');
  assert.ok(r.distanceM < DISTANCE_ARRIVEE_M, String(r.distanceM));
  assert.equal(appels.length, 0);
});

test('Google en panne, clé absente ou aucun itinéraire : « indisponible » (l\'app se replie sur une estimation)', async () => {
  await course('c1');
  await refuse(itineraireCourse(db, googleFactice({ error: { message: 'quota' } }, 429).google, 'moussa', demande(), midi), 'unavailable');
  await refuse(itineraireCourse(db, googleFactice({}).google, 'moussa', demande(), apres(60_000)), 'unavailable');
  await refuse(itineraireCourse(db, null, 'moussa', demande(), apres(120_000)), 'unavailable');
});

test('départ arrondi dans la course : l\'itinéraire mène à la position exacte du client (document privé)', async () => {
  await courseMasquee('c1');
  const arrondi = arrondirPosition(client.latitude, client.longitude);
  assert.notDeepEqual(arrondi, client, 'le test n\'a de sens que si l\'arrondi diffère de la position exacte');
  const { google, appels } = googleFactice();

  const r = await itineraireCourse(db, google, 'moussa', demande(), midi);

  assert.equal(r.vers, 'client');
  assert.deepEqual(appels[0].corps.destination.location.latLng, client);
});

test('départ arrondi : chauffeur arrivé jugé sur la position exacte, pas sur l\'arrondi', async () => {
  await courseMasquee('c1');
  const { google, appels } = googleFactice();
  const aCoteDuClient = { latitude: client.latitude + 0.0001, longitude: client.longitude }; // ~11 m du client

  const r = await itineraireCourse(db, google, 'moussa', demande({ depuis: aCoteDuClient }), midi);

  assert.equal(r.trace, '');
  assert.ok(r.distanceM < DISTANCE_ARRIVEE_M, String(r.distanceM));
  assert.equal(appels.length, 0);
});

test('départ arrondi sans document privé : refusé proprement, jamais d\'itinéraire vers la position arrondie', async () => {
  await courseMasquee('c1', {}, null);
  const { google, appels } = googleFactice();

  await refuse(itineraireCourse(db, google, 'moussa', demande(), midi), 'failed-precondition');
  assert.equal(appels.length, 0);

  // Document privé abîmé (coordonnées manquantes ou d'un autre type) : même refus.
  await departExactDe(db.doc('courses/c1')).set({ latitude: 'x' });
  await refuse(itineraireCourse(db, google, 'moussa', demande(), apres(60_000)), 'failed-precondition');
  assert.equal(appels.length, 0);
});

test('départ arrondi : le document privé n\'est lu que pour le chauffeur attribué', async () => {
  await courseMasquee('c1');
  const { google, appels } = googleFactice();

  await refuse(itineraireCourse(db, google, 'awa', demande(), midi), 'permission-denied');
  await refuse(itineraireCourse(db, google, 'intrus', demande(), midi), 'permission-denied');
  assert.equal(appels.length, 0);
});

test('client à bord, départ arrondi : l\'itinéraire mène à la destination exacte, sans toucher au document privé', async () => {
  await courseMasquee('c1', { statut: 'en_cours' }, null);
  const { google, appels } = googleFactice();

  const r = await itineraireCourse(db, google, 'moussa', demande(), midi);

  assert.equal(r.vers, 'destination');
  assert.deepEqual(appels[0].corps.destination.location.latLng, destination);
});
