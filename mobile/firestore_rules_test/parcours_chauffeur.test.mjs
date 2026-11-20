// Parcours COMPLET d'un chauffeur fraîchement inscrit, avec les écritures exactes de l'app :
//   1. création du profil (AuthRepository.inscrireConducteur, sans plaque) ;
//   2. dépôt de la PHOTO du chauffeur (clé `photoProfil`) puis de sa CARTE D'IDENTITÉ (publication 146 ; la carte grise
//      n'est plus demandée) (ConducteurDocumentsService.televerserDocument :
//      { 'documents.<cle>': <adresse Storage ou image encodée>, statutValidation: 'en_attente' }) ;
//   3. « Soumettre mon dossier » : l'app n'écrit rien (elle avance seulement l'écran) ;
//   4. vue de l'Admin : il lit le dossier, puis l'approuve.
//
// Contexte : en production (publication 142), un chauffeur recevait « firestore/permission-denied » au dépôt de ses
// pièces. Cause trouvée ici : quand Storage échoue, l'app envoyait l'image ENCODÉE (jusqu'à 700 Ko) dans le profil ;
// Firestore n'évalue ses règles que pour environ 1 000 000 de caractères d'images encodées AU TOTAL sur le profil
// (« maximum memory usage of 1000 », limite voisine du 1 Mo qu'un document Firestore ne peut de toute façon pas
// dépasser), si bien que la DEUXIÈME pièce était refusée en « permission-denied ». Aucune règle de droits n'est en
// cause : l'app doit rester sous cette limite (voir `limiteOctetsRepliBase64`).
import { after, before, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { Timestamp, doc, getDoc, runTransaction, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sprint-parcours',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const UID = 'Xk3Jq9ZpL2mVwR7sT1uYb4NcD8e0';
const EMAIL = 'nouveau.chauffeur@exemple.sn';
const moto = { marque: 'Bajaj', modele: 'Boxer 125', couleur: 'Noir' };
const connecte = (verifie) => env.authenticatedContext(UID, { email: EMAIL, email_verified: verifie });
const profilDe = (contexte) => doc(contexte.firestore(), 'users', UID);

// Ce que l'app écrit à l'inscription d'un chauffeur (sans plaque : elle n'est plus demandée).
const profilInscription = () => ({
  role: 'conducteur',
  nom: 'Moussa Diop',
  email: EMAIL,
  telephone: '+221771234567',
  vehiculeId: 'Bajaj Boxer 125 Noir',
  prenom: 'Moussa',
  nomDeFamille: 'Diop',
  moto,
  statut: 'HORS_LIGNE',
  estValide: false,
  creeLe: serverTimestamp(),
});

// Adresses de téléchargement telles que Firebase Storage les fabrique (jeton compris).
const adresse = (cle, extension = 'jpg') =>
  `https://firebasestorage.googleapis.com/v0/b/sprint-vtc.firebasestorage.app/o/kyc_documents%2F${UID}%2F${cle}.${extension}?alt=media&token=3f1c2b6e-0a54-4d7e-9a9b-5c2e8d1f7a10`;

// Mêmes constantes que l'app (lib/features/conducteur/data/piece_kyc.dart).
const LIMITE_OCTETS_REPLI = 180 * 1024;
const tailleBase64 = (octets) => Math.floor((octets + 2) / 3) * 4;
const PREFIXE = 'data:image/jpeg;base64,';
const imageEncodee = (caracteres) => PREFIXE + 'A'.repeat(caracteres);
const PIECE_DE_SECOURS = tailleBase64(LIMITE_OCTETS_REPLI); // 245 760 caractères : le plafond de l'app
// Publication 146 : toute photo est compressée à MOINS de 150 Ko avant l'envoi (compresserImageKyc).
const PHOTO_COMPRESSEE = tailleBase64(150 * 1024 - 1); // 204 800 caractères au plus

const deposer = (contexte, cle, valeur) => updateDoc(profilDe(contexte), { [`documents.${cle}`]: valeur, statutValidation: 'en_attente' });

describe('chauffeur fraîchement inscrit : dépôt des deux pièces par Storage (chemin normal)', () => {
  for (const verifie of [false, true]) {
    test(`inscription, photo, carte d'identité, soumission, vue et approbation de l'Admin, en moins de 3 s (e-mail ${verifie ? 'vérifié' : 'pas encore vérifié dans le jeton'})`, async () => {
      const debut = Date.now();
      const ctx = connecte(verifie);
      await assertSucceeds(setDoc(profilDe(ctx), profilInscription()));
      await assertSucceeds(getDoc(profilDe(ctx)));

      await assertSucceeds(deposer(ctx, 'photoProfil', adresse('photoProfil')));
      await assertSucceeds(deposer(ctx, 'carteIdentite', adresse('carteIdentite')));

      // « Soumettre mon dossier » n'écrit rien. Le chauffeur relit son profil, puis modifie son téléphone.
      const lu = (await assertSucceeds(getDoc(profilDe(ctx)))).data();
      assert.equal(lu.statutValidation, 'en_attente');
      assert.ok(lu.documents.photoProfil && lu.documents.carteIdentite);
      await assertSucceeds(updateDoc(profilDe(ctx), { telephone: '+221770000000' }));

      // L'Admin voit le dossier et l'approuve (le panneau Admin n'a pas changé).
      await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'users', 'admin1'), { role: 'admin', email: 'admin@test.sn' }));
      const admin = env.authenticatedContext('admin1', { email: 'admin@test.sn' });
      const vu = (await assertSucceeds(getDoc(doc(admin.firestore(), 'users', UID)))).data();
      assert.equal(vu.documents.photoProfil, adresse('photoProfil'));
      assert.equal(vu.documents.carteIdentite, adresse('carteIdentite'));
      await assertSucceeds(updateDoc(doc(admin.firestore(), 'users', UID), { statutValidation: 'valide', estValide: true }));
      assert.ok(Date.now() - debut < 3000, `parcours en ${Date.now() - debut} ms`);
    });
  }

  test('carte d\'identité en PDF (adresse Storage .pdf) avec la photo : acceptées', async () => {
    const ctx = connecte(true);
    await assertSucceeds(setDoc(profilDe(ctx), profilInscription()));
    await assertSucceeds(deposer(ctx, 'photoProfil', adresse('photoProfil')));
    await assertSucceeds(deposer(ctx, 'carteIdentite', adresse('carteIdentite', 'pdf')));
  });

  test('ancien dossier avec une carte grise : toujours modifiable, la carte grise reste lisible', async () => {
    const ctx = connecte(true);
    await assertSucceeds(setDoc(profilDe(ctx), profilInscription()));
    await assertSucceeds(deposer(ctx, 'carteGrise', adresse('carteGrise')));
    await assertSucceeds(deposer(ctx, 'photoProfil', adresse('photoProfil')));
    await assertSucceeds(deposer(ctx, 'carteIdentite', adresse('carteIdentite')));
    const lu = (await assertSucceeds(getDoc(profilDe(ctx)))).data();
    assert.equal(lu.documents.carteGrise, adresse('carteGrise'));
  });

  test('les deux pièces écrites ensemble, puis une pièce renvoyée plus tard : acceptées', async () => {
    const ctx = connecte(true);
    await assertSucceeds(setDoc(profilDe(ctx), profilInscription()));
    await assertSucceeds(updateDoc(profilDe(ctx), {
      'documents.photoProfil': adresse('photoProfil'),
      'documents.carteIdentite': adresse('carteIdentite'),
      statutValidation: 'en_attente',
    }));
    await assertSucceeds(deposer(ctx, 'carteIdentite', adresse('carteIdentite', 'pdf')));
  });

  test('profil déjà enrichi par le serveur (téléphone validé par SMS, bienvenue, marques) : le dépôt passe', async () => {
    const ctx = connecte(true);
    await assertSucceeds(setDoc(profilDe(ctx), profilInscription()));
    await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'users', UID), {
      telephoneVerifie: true,
      telephoneValide: '+221771234567',
      telephoneVerifieLe: new Date(),
      bienvenueEnvoyeeLe: new Date(),
      statutCompte: 'actif',
    }));
    await assertSucceeds(deposer(ctx, 'photoProfil', adresse('photoProfil')));
    await assertSucceeds(deposer(ctx, 'carteIdentite', adresse('carteIdentite')));
  });
});

describe('envoi de secours (Storage indisponible) : image encodée dans le profil', () => {
  test('photos compressées (moins de 150 Ko) : photo et carte d\'identité passent, le dossier se soumet et l\'Admin l\'approuve', async () => {
    const ctx = connecte(true);
    await assertSucceeds(setDoc(profilDe(ctx), profilInscription()));
    await assertSucceeds(deposer(ctx, 'photoProfil', imageEncodee(PHOTO_COMPRESSEE)));
    await assertSucceeds(deposer(ctx, 'carteIdentite', imageEncodee(PHOTO_COMPRESSEE)));
    // Renvoi de l'une des deux, puis modification du téléphone : toujours possible.
    await assertSucceeds(deposer(ctx, 'carteIdentite', imageEncodee(PHOTO_COMPRESSEE)));
    await assertSucceeds(updateDoc(profilDe(ctx), { telephone: '+221770000000' }));
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'users', 'admin1'), { role: 'admin', email: 'admin@test.sn' }));
    const admin = env.authenticatedContext('admin1', { email: 'admin@test.sn' });
    const vu = (await assertSucceeds(getDoc(doc(admin.firestore(), 'users', UID)))).data();
    assert.ok(vu.documents.photoProfil.startsWith(PREFIXE) && vu.documents.carteIdentite.startsWith(PREFIXE));
    await assertSucceeds(updateDoc(doc(admin.firestore(), 'users', UID), { statutValidation: 'valide', estValide: true }));
  });

  test('aux plafonds de l\'app (180 Ko par photo) : carte d\'identité, carte grise, et même photo de profil et ancienne pièce', async () => {
    const ctx = connecte(true);
    await assertSucceeds(setDoc(profilDe(ctx), profilInscription()));
    for (const cle of ['photoProfil', 'carteIdentite', 'carteGrise', 'permis']) {
      await assertSucceeds(deposer(ctx, cle, imageEncodee(PIECE_DE_SECOURS)), cle);
    }
    // Et le profil reste modifiable ensuite.
    await assertSucceeds(updateDoc(profilDe(ctx), { telephone: '+221770000000' }));
  });

  test('LIMITE DE FIRESTORE (cause du « permission-denied » de la 142) : deux images de 700 Ko encodées dépassent ce que les règles savent évaluer', async () => {
    const ctx = connecte(true);
    await assertSucceeds(setDoc(profilDe(ctx), profilInscription()));
    const grosse = imageEncodee(tailleBase64(700 * 1024)); // le plafond d'avant, 933 000 caractères
    await assertSucceeds(deposer(ctx, 'photoProfil', grosse), 'la première passe');
    // La deuxième est refusée en « permission-denied », sans qu'aucune règle de droits soit en cause : c'est la mémoire
    // d'évaluation des règles (et, de toute façon, deux images de 933 000 caractères ne tiennent pas dans 1 Mo).
    await assertFails(deposer(ctx, 'carteIdentite', grosse));
  });

  test('un dépôt par Storage reste possible même sur un profil portant déjà une image de secours moyenne', async () => {
    const ctx = connecte(true);
    await assertSucceeds(setDoc(profilDe(ctx), profilInscription()));
    await assertSucceeds(deposer(ctx, 'photoProfil', imageEncodee(PIECE_DE_SECOURS)));
    await assertSucceeds(deposer(ctx, 'carteIdentite', adresse('carteIdentite')));
  });
});

// Publication 147, iPhone, compte de test du client : « firestore/permission-denied » SANS suffixe dès l'ajout de la
// Photo (Storage avait donc accepté). Un vrai profil de chauffeur, tel que la production le contient (champs écrits par
// le serveur compris), accepte pourtant ses deux pièces : le refus n'arrive que pour un compte CLIENT connecté dans
// l'espace chauffeur, ou pour un compte de connexion SANS profil (inscription interrompue juste après la création du
// compte). Ces deux cas sont désormais reconnus par l'app (lot 148 : écran « Ce compte est un compte Client » et
// formulaire « Terminez votre inscription ») ; les règles restent inchangées.
describe('compte réel de production (lot 148)', () => {
  // Ce que le serveur ajoute au profil après l'inscription : validation du numéro (validerTelephone) et
  // « Bienvenue chez SPRINT » (declencherBienvenue), écrits par l'Admin SDK.
  const champsServeur = () => ({
    telephoneVerifie: true,
    telephoneValide: '+221771234567',
    telephoneVerifieLe: Timestamp.now(),
    bienvenueEnvoyeeLe: Timestamp.now(),
  });
  const profilProduction = (extra = {}) => ({ ...profilInscription(), creeLe: Timestamp.now(), ...champsServeur(), ...extra });

  for (const [cas, extra] of [
    ['compte neuf', {}],
    ['dossier rejeté puis repris', { statutValidation: 'rejete' }],
    ['ancien dossier avec une carte grise encodée', { documents: { carteGrise: imageEncodee(PIECE_DE_SECOURS) } }],
  ]) {
    test(`vrai profil de chauffeur (${cas}) : photo puis carte d'identité acceptées, l'Admin approuve`, async () => {
      await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'users', UID), profilProduction(extra)));
      const ctx = connecte(false);
      await assertSucceeds(deposer(ctx, 'photoProfil', adresse('photoProfil')));
      await assertSucceeds(deposer(ctx, 'carteIdentite', adresse('carteIdentite')));
      await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'users', 'admin1'), { role: 'admin', email: 'admin@test.sn' }));
      const admin = env.authenticatedContext('admin1', { email: 'admin@test.sn' });
      await assertSucceeds(updateDoc(doc(admin.firestore(), 'users', UID), { statutValidation: 'valide', estValide: true }));
    });
  }

  test('compte CLIENT connecté dans l\'espace chauffeur : ses pièces sont refusées (le refus de la capture)', async () => {
    await env.withSecurityRulesDisabled((c) =>
      setDoc(doc(c.firestore(), 'users', UID), { role: 'client', nom: 'Awa Ndiaye', email: EMAIL, telephone: '+221771234567', statut: 'HORS_LIGNE', estValide: false, creeLe: Timestamp.now() }));
    const ctx = connecte(true);
    await assertFails(deposer(ctx, 'photoProfil', adresse('photoProfil')));
    await assertFails(deposer(ctx, 'carteIdentite', adresse('carteIdentite')));
    // Et il ne peut pas se déclarer chauffeur lui-même : le rôle est réservé à l'Admin.
    await assertFails(updateDoc(profilDe(ctx), { role: 'conducteur' }));
    // L'app relit son profil pour dire pourquoi (« compte client ») : lecture permise.
    assert.equal((await assertSucceeds(getDoc(profilDe(ctx)))).data().role, 'client');
  });

  test('compte SANS profil : pièces refusées ; « Terminez votre inscription » crée le profil, puis les pièces passent', async () => {
    const ctx = connecte(false);
    await assertFails(deposer(ctx, 'photoProfil', adresse('photoProfil')));
    // L'app relit le profil pour dire pourquoi (« profil absent ») : lecture permise, document inexistant.
    assert.equal((await assertSucceeds(getDoc(profilDe(ctx)))).exists(), false);
    // AuthRepository.completerProfilConducteur : transaction qui ne crée le profil que s'il n'existe pas.
    await assertSucceeds(runTransaction(ctx.firestore(), async (tx) => {
      if ((await tx.get(profilDe(ctx))).exists()) return;
      tx.set(profilDe(ctx), profilInscription());
    }));
    await assertSucceeds(deposer(ctx, 'photoProfil', adresse('photoProfil')));
    await assertSucceeds(deposer(ctx, 'carteIdentite', adresse('carteIdentite')));
  });

  test('un profil existant n\'est jamais remplacé par une nouvelle inscription (pièces et statut conservés)', async () => {
    const ctx = connecte(true);
    await assertSucceeds(setDoc(profilDe(ctx), profilInscription()));
    await assertSucceeds(deposer(ctx, 'photoProfil', adresse('photoProfil')));
    await assertFails(setDoc(profilDe(ctx), profilInscription()));
    assert.equal((await getDoc(profilDe(ctx))).data().documents.photoProfil, adresse('photoProfil'));
  });
});
