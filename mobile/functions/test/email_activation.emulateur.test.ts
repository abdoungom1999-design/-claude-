// E-mail d'activation d'un chauffeur, sur l'émulateur Firestore : npm run test:emulateur.
// Resend et Firebase Auth sont remplacés par des faux ; Firestore est le vrai (émulateur).
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { envoyerEmailActivation, type ComptesEmail } from '../src/email_activation';
import { ErreurResend, type CourrielResend, type EnvoiCourriel } from '../src/email_resend';

let app: App;
let db: Firestore;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' }, 'email-activation');
  db = getFirestore(app);
});
after(() => deleteApp(app));
beforeEach(() => db.recursiveDelete(db.collection('users')));

const comptes: ComptesEmail = { adresseVerifiee: async () => 'moussa@exemple.sn' };

function envoiFactice(echecs: ErreurResend[] = []) {
  const envois: { courriel: CourrielResend; cle: string }[] = [];
  const restants = [...echecs];
  const envoi: EnvoiCourriel = {
    envoyer: async (courriel, cle) => {
      envois.push({ courriel, cle });
      const echec = restants.shift();
      if (echec) throw echec;
      return { id: `msg_${envois.length}` };
    },
  };
  return { envoi, envois };
}

const poser = (uid: string, valeurs: Record<string, unknown>) =>
  db.collection('users').doc(uid).set({ role: 'conducteur', nom: 'Moussa Diop', prenom: 'Moussa', statutValidation: 'valide', creeLe: Timestamp.now(), ...valeurs });

const AVANT = { role: 'conducteur', statutValidation: 'en_attente' };
const APRES = { role: 'conducteur', statutValidation: 'valide' };

test('approbation : l\'e-mail part, et la date et l\'identifiant Resend sont inscrits au profil par le serveur', async () => {
  await poser('m1', {});
  const { envoi, envois } = envoiFactice();
  const r = await envoyerEmailActivation({ db, comptes, envoi }, 'm1', AVANT, APRES);

  assert.deepEqual(r, { envoye: true, id: 'msg_1' });
  assert.equal(envois.length, 1);
  assert.deepEqual(envois[0].courriel.to, ['moussa@exemple.sn']);
  const profil = (await db.collection('users').doc('m1').get()).data() ?? {};
  assert.equal(profil.emailActivationId, 'msg_1');
  assert.ok(profil.emailActivationEnvoyeLe instanceof Timestamp);
  // Le reste du profil n'a pas bougé.
  assert.equal(profil.statutValidation, 'valide');
  assert.equal(profil.nom, 'Moussa Diop');
});

test('le même événement livré une seconde fois (au moins une fois) : un seul e-mail', async () => {
  await poser('m2', {});
  const { envoi, envois } = envoiFactice();
  const dependances = { db, comptes, envoi };

  assert.equal((await envoyerEmailActivation(dependances, 'm2', AVANT, APRES)).envoye, true);
  const second = await envoyerEmailActivation(dependances, 'm2', AVANT, APRES);
  assert.deepEqual(second, { envoye: false, raison: 'deja_envoye' });
  assert.equal(envois.length, 1);
});

test('deux livraisons simultanées : au plus deux appels, avec la MÊME clé d\'idempotence (Resend n\'envoie qu\'un message)', async () => {
  await poser('m3', {});
  const { envoi, envois } = envoiFactice();
  await Promise.all([
    envoyerEmailActivation({ db, comptes, envoi }, 'm3', AVANT, APRES),
    envoyerEmailActivation({ db, comptes, envoi }, 'm3', AVANT, APRES),
  ]);
  assert.ok(envois.length >= 1 && envois.length <= 2);
  assert.deepEqual([...new Set(envois.map((e) => e.cle))], ['activation-chauffeur-m3']);
});

test('échec de Resend : rien n\'est inscrit, et un nouvel essai (autre événement) réussit', async () => {
  await poser('m4', {});
  const { envoi, envois } = envoiFactice([new ErreurResend('resend/429', 'rate_limit_exceeded')]);

  const echec = await envoyerEmailActivation({ db, comptes, envoi }, 'm4', AVANT, APRES);
  assert.deepEqual(echec, { envoye: false, raison: 'echec', code: 'resend/429' });
  const sansMarque = (await db.collection('users').doc('m4').get()).data() ?? {};
  assert.equal(sansMarque.emailActivationEnvoyeLe, undefined);

  const reussite = await envoyerEmailActivation({ db, comptes, envoi }, 'm4', AVANT, APRES);
  assert.deepEqual(reussite, { envoye: true, id: 'msg_2' });
  assert.equal(envois.length, 2);
});

test('dossier rejeté ou compte suspendu depuis l\'approbation : rien n\'est envoyé', async () => {
  await poser('m5', { statutValidation: 'rejete' });
  await poser('m6', { statutCompte: 'suspendu' });
  const { envoi, envois } = envoiFactice();
  assert.deepEqual(await envoyerEmailActivation({ db, comptes, envoi }, 'm5', AVANT, APRES), { envoye: false, raison: 'dossier_non_valide' });
  assert.deepEqual(await envoyerEmailActivation({ db, comptes, envoi }, 'm6', AVANT, APRES), { envoye: false, raison: 'compte_bloque' });
  assert.equal(envois.length, 0);
});

test('profil introuvable : rien n\'est envoyé, aucune erreur', async () => {
  const { envoi, envois } = envoiFactice();
  const r = await envoyerEmailActivation({ db, comptes, envoi }, 'fantome', AVANT, APRES);
  assert.deepEqual(r, { envoye: false, raison: 'dossier_non_valide' });
  assert.equal(envois.length, 0);
});
