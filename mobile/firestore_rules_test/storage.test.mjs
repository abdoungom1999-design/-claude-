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
const pdf = { contentType: 'application/pdf' };
const stockage = (uid) => (uid ? env.authenticatedContext(uid).storage() : env.unauthenticatedContext().storage());
const piece = (uid, fichier, depuis = uid) => ref(stockage(depuis), `kyc_documents/${uid}/${fichier}`);

describe('Storage : pièces KYC des chauffeurs', () => {
  test('le chauffeur envoie, relit, remplace et supprime ses pièces (photos)', async () => {
    for (const f of ['carteIdentite.jpg', 'carteGrise.jpg', 'permis.jpg', 'attestationVtc.jpg', 'photoProfil.jpg']) {
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

  test('seulement les pièces prévues : pas d\'autre nom de fichier, pas d\'autre dossier', async () => {
    await assertFails(uploadBytes(piece('moussa', 'autre.jpg'), octets(), jpeg));
    await assertFails(uploadBytes(piece('moussa', 'carteIdentite.png'), octets(), jpeg));
    // Les anciennes pièces n'existent pas en PDF : seules la carte d'identité et la carte grise l'acceptent.
    await assertFails(uploadBytes(piece('moussa', 'permis.pdf'), octets(), pdf));
    await assertFails(uploadBytes(piece('moussa', 'attestationVtc.pdf'), octets(), pdf));
    await assertFails(uploadBytes(piece('moussa', 'photoProfil.pdf'), octets(), pdf));
    await assertFails(uploadBytes(piece('moussa', 'permis.png'), octets(), jpeg));
    await assertFails(uploadBytes(ref(stockage('moussa'), 'divers/moussa/permis.jpg'), octets(), jpeg));
    await assertFails(uploadBytes(ref(stockage('moussa'), 'permis.jpg'), octets(), jpeg));
  });

  test('photos : JPEG, PNG et WebP acceptés sous les noms .jpg ; PDF, HEIC, texte et page web refusés', async () => {
    for (const type of ['image/jpeg', 'image/png', 'image/webp']) {
      await assertSucceeds(uploadBytes(piece('moussa', 'carteIdentite.jpg'), octets(), { contentType: type }), type);
    }
    for (const type of ['application/pdf', 'text/html', 'image/heic', 'image/heif', 'image/gif', 'image/svg+xml', 'application/octet-stream']) {
      await assertFails(uploadBytes(piece('moussa', 'carteIdentite.jpg'), octets(), { contentType: type }), type);
    }
  });

  test('PDF : carte d\'identité et carte grise seulement, sous un nom .pdf, avec le type PDF', async () => {
    for (const f of ['carteIdentite.pdf', 'carteGrise.pdf']) {
      await assertSucceeds(uploadBytes(piece('moussa', f), octets(), pdf));
      await assertSucceeds(getBytes(piece('moussa', f)));
      await assertSucceeds(deleteObject(piece('moussa', f)));
    }
    // Un PDF annoncé comme image, ou une image annoncée comme PDF : refusé (le type doit correspondre au nom).
    await assertFails(uploadBytes(piece('moussa', 'carteIdentite.pdf'), octets(), jpeg));
    await assertFails(uploadBytes(piece('moussa', 'carteGrise.jpg'), octets(), pdf));
    await assertFails(uploadBytes(piece('moussa', 'carteGrise.pdf'), octets(), { contentType: 'text/html' }));
  });

  test('type absent : refusé (cause possible d\'un échec d\'envoi sur un navigateur qui ne l\'annonce pas)', async () => {
    await assertFails(uploadBytes(piece('moussa', 'carteIdentite.jpg'), octets(), {}));
    await assertFails(uploadBytes(piece('moussa', 'carteGrise.pdf'), octets()));
  });

  test('10 Mo au plus, photo comme PDF', async () => {
    const DIX_MO = 10 * 1024 * 1024;
    await assertSucceeds(uploadBytes(piece('moussa', 'carteGrise.jpg'), octets(DIX_MO), jpeg));
    await assertFails(uploadBytes(piece('moussa', 'attestationVtc.jpg'), octets(DIX_MO + 1), jpeg));
    await assertSucceeds(uploadBytes(piece('moussa', 'carteIdentite.pdf'), octets(DIX_MO), pdf));
    await assertFails(uploadBytes(piece('moussa', 'carteGrise.pdf'), octets(DIX_MO + 1), pdf));
  });

  test('les PDF aussi sont réservés à leur propriétaire', async () => {
    await assertSucceeds(uploadBytes(piece('moussa', 'carteIdentite.pdf'), octets(), pdf));
    for (const intrus of ['awa', 'autreChauffeur', null]) {
      const cible = piece('moussa', 'carteIdentite.pdf', intrus);
      await assertFails(getBytes(cible));
      await assertFails(uploadBytes(cible, octets(), pdf));
      await assertFails(deleteObject(cible));
    }
  });
});
