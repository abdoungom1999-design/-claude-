// Migration des pièces KYC Base64 -> Storage, sur l'émulateur Firestore
// (le bucket est simulé) : npm run test:emulateur.
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { LOT_CHAUFFEURS, migrerDocumentsKyc, type StockageKyc } from '../src/kyc_stockage';

const maintenant = new Date(Date.UTC(2026, 9, 4, 12));
const IMAGE = `data:image/jpeg;base64,${Buffer.from('octets-image').toString('base64')}`;
const URL_STORAGE = 'https://firebasestorage.googleapis.com/v0/b/x/o/deja?alt=media&token=t';

class StockageFactice implements StockageKyc {
  fichiers = new Map<string, { octets: Buffer; typeMime: string; jeton: string }>();
  enPanne = false;

  async enregistrer(chemin: string, octets: Buffer, typeMime: string, jeton: string): Promise<void> {
    if (this.enPanne) throw new Error('bucket introuvable');
    this.fichiers.set(chemin, { octets, typeMime, jeton });
  }

  urlTelechargement(chemin: string, jeton: string): string {
    return `https://stockage.test/${encodeURIComponent(chemin)}?token=${jeton}`;
  }
}

let app: App;
let db: Firestore;
let stockage: StockageFactice;
let compteur: number;
const jeton = () => `jeton-${++compteur}`;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' }, 'kyc-stockage');
  db = getFirestore(app);
});

after(() => deleteApp(app));

beforeEach(async () => {
  stockage = new StockageFactice();
  compteur = 0;
  for (const nom of ['users', 'journal_admin']) {
    const docs = await db.collection(nom).listDocuments();
    await Promise.all(docs.map((d) => db.recursiveDelete(d)));
  }
  await db.doc('users/chef').set({ role: 'admin' });
  await db.doc('users/awa').set({ role: 'client' });
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

const documents = async (uid: string) => (await db.doc(`users/${uid}`).get()).get('documents') as Record<string, string>;

test('réservé à l\'Admin', async () => {
  await refuse(migrerDocumentsKyc(db, stockage, undefined, {}, maintenant), 'unauthenticated');
  await refuse(migrerDocumentsKyc(db, stockage, 'awa', {}, maintenant), 'permission-denied');
});

test('aperçu : compte les pièces Base64 sans rien écrire (Storage non requis)', async () => {
  await db.doc('users/m1').set({ role: 'conducteur', documents: { permis: IMAGE, carteGrise: URL_STORAGE } });
  await db.doc('users/m2').set({ role: 'conducteur', documents: { permis: IMAGE, attestationVtc: IMAGE } });
  stockage.enPanne = true;
  const bilan = await migrerDocumentsKyc(db, stockage, 'chef', { apercu: true }, maintenant, jeton);
  assert.deepEqual(bilan, { documentsABMigrer: 3, chauffeursConcernes: 2, migres: 0, ignores: 0, restants: 3, apercu: true });
  assert.equal((await documents('m1')).permis, IMAGE);
  assert.equal((await db.collection('journal_admin').get()).size, 0);
});

test('migration : pièce envoyée à l\'emplacement attendu, URL enregistrée à la place de l\'image, journal', async () => {
  await db.doc('users/m1').set({
    role: 'conducteur',
    nom: 'Moussa',
    statutValidation: 'valide',
    documents: { permis: IMAGE, carteGrise: URL_STORAGE },
  });
  const bilan = await migrerDocumentsKyc(db, stockage, 'chef', {}, maintenant, jeton);
  assert.deepEqual(bilan, { documentsABMigrer: 1, chauffeursConcernes: 1, migres: 1, ignores: 0, restants: 0, apercu: false });

  const fichier = stockage.fichiers.get('kyc_documents/m1/permis.jpg');
  assert.ok(fichier);
  assert.equal(fichier.octets.toString(), 'octets-image');
  assert.equal(fichier.typeMime, 'image/jpeg');
  const d = await documents('m1');
  assert.equal(d.permis, 'https://stockage.test/kyc_documents%2Fm1%2Fpermis.jpg?token=jeton-1');
  assert.equal(d.carteGrise, URL_STORAGE, 'une pièce déjà dans Storage n\'est pas touchée');
  const profil = (await db.doc('users/m1').get()).data()!;
  assert.equal(profil.statutValidation, 'valide', 'la validation du dossier n\'est pas remise en cause');

  const journal = (await db.collection('journal_admin').get()).docs.map((x) => x.data());
  assert.equal(journal.length, 1);
  assert.equal(journal[0].action, 'migration_kyc_storage');
  assert.equal(journal[0].adminId, 'chef');
  assert.equal(journal[0].documentsMigres, 1);
});

test('rejouable : une deuxième exécution ne trouve plus rien à migrer', async () => {
  await db.doc('users/m1').set({ role: 'conducteur', documents: { permis: IMAGE } });
  await migrerDocumentsKyc(db, stockage, 'chef', {}, maintenant, jeton);
  const bilan = await migrerDocumentsKyc(db, stockage, 'chef', {}, maintenant, jeton);
  assert.equal(bilan.documentsABMigrer, 0);
  assert.equal(bilan.migres, 0);
  assert.equal(stockage.fichiers.size, 1);
});

test('Storage indisponible : refus explicite, aucune pièce modifiée', async () => {
  await db.doc('users/m1').set({ role: 'conducteur', documents: { permis: IMAGE } });
  stockage.enPanne = true;
  const e = await refuse(migrerDocumentsKyc(db, stockage, 'chef', {}, maintenant, jeton), 'failed-precondition');
  assert.match(e.message, /Firebase Storage/);
  assert.equal((await documents('m1')).permis, IMAGE);
});

test('une pièce renvoyée par le chauffeur pendant la migration n\'est pas écrasée', async () => {
  await db.doc('users/m1').set({ role: 'conducteur', documents: { permis: IMAGE } });
  const NOUVELLE = 'https://firebasestorage.googleapis.com/v0/b/x/o/nouvelle?alt=media&token=n';
  const original = stockage.enregistrer.bind(stockage);
  stockage.enregistrer = async (...args) => {
    await original(...args);
    await db.doc('users/m1').update({ 'documents.permis': NOUVELLE });
  };
  const bilan = await migrerDocumentsKyc(db, stockage, 'chef', {}, maintenant, jeton);
  assert.equal(bilan.migres, 0);
  assert.equal((await documents('m1')).permis, NOUVELLE);
});

test('image illisible : ignorée, laissée telle quelle (une pièce > 1 Mo ne peut pas exister dans Firestore)', async () => {
  await db.doc('users/m1').set({ role: 'conducteur', documents: { permis: 'data:image/jpeg;base64,!!!', attestationVtc: IMAGE } });
  const bilan = await migrerDocumentsKyc(db, stockage, 'chef', {}, maintenant, jeton);
  assert.equal(bilan.documentsABMigrer, 2);
  assert.equal(bilan.migres, 1, 'la pièce lisible est migrée');
  assert.equal(bilan.ignores, 1);
  assert.equal(bilan.restants, 1);
  assert.equal((await documents('m1')).permis, 'data:image/jpeg;base64,!!!');
});

test('par lots : au plus 10 chauffeurs par appel, on relance jusqu\'à « restants : 0 »', async () => {
  for (let i = 0; i < LOT_CHAUFFEURS + 3; i++) {
    await db.doc(`users/m${i}`).set({ role: 'conducteur', documents: { permis: IMAGE } });
  }
  const premier = await migrerDocumentsKyc(db, stockage, 'chef', {}, maintenant, jeton);
  assert.equal(premier.migres, LOT_CHAUFFEURS);
  assert.equal(premier.restants, 3);
  const second = await migrerDocumentsKyc(db, stockage, 'chef', {}, maintenant, jeton);
  assert.equal(second.migres, 3);
  assert.equal(second.restants, 0);
});
