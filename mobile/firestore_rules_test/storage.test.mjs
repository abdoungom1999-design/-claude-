// Tests des règles Firebase Storage (../storage.rules) sur l'émulateur Storage.
// Lancement : npm test (voir package.json).
import { after, before, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { deleteObject, getBytes, listAll, ref, uploadBytes } from 'firebase/storage';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sprint-storage',
    storage: { rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8') },
  });
});

after(() => env.cleanup());

const octets = (n = 16) => new Uint8Array(n).fill(7);
const jpeg = { contentType: 'image/jpeg' };
const stockage = (uid) => (uid ? env.authenticatedContext(uid).storage() : env.unauthenticatedContext().storage());
const piece = (uid, fichier, depuis = uid) => ref(stockage(depuis), `kyc_documents/${uid}/${fichier}`);

describe('Storage : pièces KYC des chauffeurs', () => {
  test('le chauffeur envoie, relit, remplace et supprime ses 4 pièces', async () => {
    for (const f of ['permis.jpg', 'carteGrise.jpg', 'attestationVtc.jpg', 'photoProfil.jpg']) {
      await assertSucceeds(uploadBytes(piece('moussa', f), octets(), jpeg));
      await assertSucceeds(getBytes(piece('moussa', f)));
    }
    await assertSucceeds(uploadBytes(piece('moussa', 'permis.jpg'), octets(32), jpeg));
    await assertSucceeds(deleteObject(piece('moussa', 'permis.jpg')));
  });

  test('ni les autres comptes ni les visiteurs ne lisent, écrivent ou suppriment la pièce d\'un chauffeur', async () => {
    await assertSucceeds(uploadBytes(piece('moussa', 'permis.jpg'), octets(), jpeg));
    for (const intrus of ['awa', 'autreChauffeur', null]) {
      const cible = piece('moussa', 'permis.jpg', intrus);
      await assertFails(getBytes(cible));
      await assertFails(uploadBytes(cible, octets(), jpeg));
      await assertFails(deleteObject(cible));
    }
  });

  test('pas de liste des fichiers, même pour le propriétaire', async () => {
    await assertSucceeds(uploadBytes(piece('moussa', 'permis.jpg'), octets(), jpeg));
    await assertFails(listAll(ref(stockage('moussa'), 'kyc_documents/moussa')));
  });

  test('seulement les 4 pièces prévues : pas d\'autre nom de fichier, pas d\'autre dossier', async () => {
    await assertFails(uploadBytes(piece('moussa', 'autre.jpg'), octets(), jpeg));
    await assertFails(uploadBytes(piece('moussa', 'permis.png'), octets(), jpeg));
    await assertFails(uploadBytes(ref(stockage('moussa'), 'divers/moussa/permis.jpg'), octets(), jpeg));
    await assertFails(uploadBytes(ref(stockage('moussa'), 'permis.jpg'), octets(), jpeg));
  });

  test('images seulement, 5 Mo au plus', async () => {
    await assertFails(uploadBytes(piece('moussa', 'permis.jpg'), octets(), { contentType: 'application/pdf' }));
    await assertFails(uploadBytes(piece('moussa', 'permis.jpg'), octets(), { contentType: 'text/html' }));
    await assertSucceeds(uploadBytes(piece('moussa', 'permis.jpg'), octets(), { contentType: 'image/png' }));
    await assertSucceeds(uploadBytes(piece('moussa', 'carteGrise.jpg'), octets(5 * 1024 * 1024), jpeg));
    await assertFails(uploadBytes(piece('moussa', 'attestationVtc.jpg'), octets(5 * 1024 * 1024 + 1), jpeg));
  });
});
