// Chauffeurs à proximité sur l'émulateur Firestore : npm run test:emulateur.
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { chauffeursProches, MAX_CHAUFFEURS } from '../src/proximite';

const maintenant = new Date(Date.UTC(2026, 8, 29, 12));
const client = { latitude: 14.6928, longitude: -17.4467 }; // Plateau

let app: App;
let db: Firestore;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' }, 'proximite');
  db = getFirestore(app);
});

after(() => deleteApp(app));

beforeEach(async () => {
  const docs = await db.collection('positions_chauffeurs').listDocuments();
  await Promise.all(docs.map((d) => d.delete()));
});

async function position(uid: string, latitude: number, longitude: number, extra: Record<string, unknown> = {}) {
  await db.doc(`positions_chauffeurs/${uid}`).set({
    latitude,
    longitude,
    cap: 92,
    majLe: Timestamp.fromDate(new Date(maintenant.getTime() - 20_000)),
    ...extra,
  });
}

test('chauffeurs disponibles alentour : sans identité, positions arrondies, cap à 45°', async () => {
  await position('moussa', 14.6951, -17.4452); // ~300 m
  const r = await chauffeursProches(db, 'awa', client, maintenant);
  assert.equal(r.chauffeurs.length, 1);
  const [c] = r.chauffeurs;
  assert.deepEqual(Object.keys(c).sort(), ['cap', 'latitude', 'longitude']);
  assert.equal(c.cap, 90);
  assert.notEqual(c.latitude, 14.6951);
  assert.ok(Math.abs(c.latitude - 14.6951) < 0.001 && Math.abs(c.longitude + 17.4452) < 0.001);
  assert.ok(!JSON.stringify(r).includes('moussa'));
  assert.equal(r.approcheMinutes, 2);
});

test('ignorés : chauffeur en course, position périmée, trop loin', async () => {
  await position('enCourse', 14.6930, -17.4460, { courseId: 'c1' });
  await position('perime', 14.6931, -17.4461, { majLe: Timestamp.fromDate(new Date(maintenant.getTime() - 3 * 60_000)) });
  await position('loin', 14.7600, -17.4467); // ~7,5 km (même bande de latitude exclue)
  await position('loinEstOuest', 14.6928, -17.3900); // ~6 km à l'est
  const r = await chauffeursProches(db, 'awa', client, maintenant);
  assert.deepEqual(r.chauffeurs, []);
  assert.equal(r.approcheMinutes, null);
});

test('deux chauffeurs dans la même case : une seule icône ; plafond d\'icônes', async () => {
  await position('a', 14.69280, -17.44670);
  await position('b', 14.69282, -17.44668);
  assert.equal((await chauffeursProches(db, 'awa', client, maintenant)).chauffeurs.length, 1);

  // Cases distinctes (pas de 167 m, plus grand qu'une case) et toutes à moins de 3 km.
  for (let i = 0; i < MAX_CHAUFFEURS + 3; i++) await position(`c${i}`, 14.6928 + i * 0.0015, -17.4440);
  assert.equal((await chauffeursProches(db, 'awa', client, maintenant)).chauffeurs.length, MAX_CHAUFFEURS);
});

test('non connecté ou coordonnées invalides : refusé', async () => {
  const refuse = async (p: Promise<unknown>, code: string) => {
    await assert.rejects(p, (e) => e instanceof HttpsError && e.code === code);
  };
  await refuse(chauffeursProches(db, undefined, client, maintenant), 'unauthenticated');
  await refuse(chauffeursProches(db, 'awa', {}, maintenant), 'invalid-argument');
  await refuse(chauffeursProches(db, 'awa', { latitude: 200, longitude: 0 }, maintenant), 'invalid-argument');
  await refuse(chauffeursProches(db, 'awa', { latitude: '14', longitude: -17 }, maintenant), 'invalid-argument');
});
