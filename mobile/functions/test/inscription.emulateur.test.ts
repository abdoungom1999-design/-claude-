// Validation du téléphone et bienvenue, sur les émulateurs Firestore et Auth : npm run test:emulateur.
// Le contrôle du code SMS par Firebase est remplacé par une preuve fabriquée, SAUF dans les tests
// « émulateur Auth » : ceux-là font un vrai parcours par téléphone dans l'émulateur et vérifient
// que le serveur lit bien le jeton que Firebase fabrique (fournisseur, numéro, heure).
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, getApp, initializeApp, type App } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { LIENS, type EnvoiPush, type Messagerie } from '../src/notifications';
import {
  ComptesFirebase,
  declencherBienvenue,
  FRAICHEUR_CODE_MS,
  validerTelephone,
  verifierJetonFirebase,
  type CompteAuth,
  type ComptesAuth,
  type PreuveTelephone,
  type VerifierJetonTelephone,
} from '../src/inscription';

const t0 = new Date(Date.UTC(2026, 10, 20, 12));
const apres = (ms: number) => new Date(t0.getTime() + ms);
const MINUTE = 60_000;
const OUVERTURE = new Date(Date.UTC(2026, 10, 20, 8));

const TEL_AWA = '+221771234567';
const TEL_MOUSSA = '+221762345678';

let app: App;
let db: Firestore;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' }, 'inscription');
  db = getFirestore(app);
  // Application par défaut : celle que les vrais accès Firebase (getAuth()) utilisent en production.
  initializeApp({ projectId: 'demo-sprint' });
});
after(async () => {
  await deleteApp(app);
  await deleteApp(getApp());
});

async function vider() {
  for (const nom of ['users', 'telephones_valides', 'mail', 'appareils', 'portefeuilles', 'profils_publics']) {
    await db.recursiveDelete(db.collection(nom));
  }
}

// --- Faux -------------------------------------------------------------------------------

let preuve: PreuveTelephone | Error;
let jetonsLus: string[];
const verifier: VerifierJetonTelephone = async (jeton) => {
  jetonsLus.push(jeton);
  if (preuve instanceof Error) throw preuve;
  return preuve;
};
const preuveDe = (telephone: string | undefined, extra: Partial<PreuveTelephone> = {}): PreuveTelephone => ({
  uid: 'session-telephone-1',
  fournisseur: 'phone',
  telephone,
  connecteLe: t0,
  ...extra,
});

let sessionsSupprimees: string[];
let suppressionEnPanne: boolean;
let compte: CompteAuth;
const comptes: ComptesAuth = {
  lire: async () => compte,
  supprimerSessionTelephone: async (uid) => {
    if (suppressionEnPanne) throw new Error('Auth indisponible');
    sessionsSupprimees.push(uid);
    return true;
  },
};

interface Envoi {
  jetons: string[];
  push: EnvoiPush;
}
class MessagerieFausse implements Messagerie {
  envois: Envoi[] = [];
  enPanne = false;
  async envoyer(jetons: string[], push: EnvoiPush) {
    if (this.enPanne) throw new Error('FCM indisponible');
    this.envois.push({ jetons: [...jetons], push });
    return { envoyes: jetons.length, invalides: [] };
  }
}
let fcm: MessagerieFausse;

const JETON = 'jeton-de-test-'.padEnd(60, 'x');

async function creerProfil(uid: string, role: string, telephone: string, extra: Record<string, unknown> = {}) {
  await db.doc(`users/${uid}`).set({
    role, nom: uid === 'moussa' ? 'Moussa Diop' : 'Awa Ndiaye', email: `${uid}@test.sn`, telephone,
    statut: role === 'client' ? 'ACTIF' : 'HORS_LIGNE', creeLe: Timestamp.fromDate(t0), ...extra,
  });
}

beforeEach(async () => {
  await vider();
  preuve = preuveDe(TEL_AWA);
  jetonsLus = [];
  sessionsSupprimees = [];
  suppressionEnPanne = false;
  compte = { creeLe: apres(-60 * MINUTE), emailVerifie: true, email: 'awa@test.sn' };
  fcm = new MessagerieFausse();
  await creerProfil('awa', 'client', '77 123 45 67');
});

const valider = (uid = 'awa', quand = t0, donnees: unknown = { jeton: JETON }) =>
  validerTelephone(db, verifier, comptes, uid, donnees, quand, 'obligatoire');
const validerSansConnexion = () => validerTelephone(db, verifier, comptes, undefined, { jeton: JETON }, t0, 'obligatoire');

async function refuse(promesse: Promise<unknown>, code: string): Promise<HttpsError> {
  try {
    await promesse;
  } catch (e) {
    assert.ok(e instanceof HttpsError, String(e));
    assert.equal(e.code, code, e.message);
    return e;
  }
  assert.fail(`refus ${code} attendu`);
}

const profil = async (uid = 'awa') => (await db.doc(`users/${uid}`).get()).data() ?? {};

// --- Validation du numéro -------------------------------------------------------------------

test('validation : le numéro du jeton est posé sur le compte, avec les marques du serveur et la preuve d\'unicité', async () => {
  assert.deepEqual(await valider(), { valide: true, telephone: TEL_AWA });
  const p = await profil();
  assert.equal(p.telephoneVerifie, true);
  assert.equal(p.telephoneValide, TEL_AWA);
  assert.equal((p.telephoneVerifieLe as Timestamp).toMillis(), t0.getTime());
  assert.equal(p.telephone, '77 123 45 67', 'le numéro saisi par la personne n\'est pas réécrit');
  const cle = (await db.doc(`telephones_valides/client_${TEL_AWA}`).get()).data();
  assert.equal(cle?.uid, 'awa');
  assert.equal(cle?.role, 'client');
  assert.deepEqual(jetonsLus, [JETON]);
  assert.deepEqual(sessionsSupprimees, ['session-telephone-1'], 'la session « téléphone » est supprimée');
});

test('validation : le même numéro peut être validé sur un compte Client ET sur un compte Chauffeur', async () => {
  await creerProfil('moussa', 'conducteur', '77 123 45 67');
  await valider('awa');
  await valider('moussa');
  assert.equal((await profil('moussa')).telephoneVerifie, true);
  assert.ok((await db.doc(`telephones_valides/conducteur_${TEL_AWA}`).get()).exists);
  assert.ok((await db.doc(`telephones_valides/client_${TEL_AWA}`).get()).exists);
});

test('validation : un numéro déjà validé sur un autre compte du même rôle est refusé, sans rien marquer', async () => {
  await valider('awa');
  await creerProfil('fatou', 'client', TEL_AWA);
  const e = await refuse(valider('fatou'), 'already-exists');
  assert.match(e.message, /déjà validé sur un autre compte/);
  const f = await profil('fatou');
  assert.equal(f.telephoneVerifie, undefined);
  assert.equal(f.telephoneValide, undefined);
  assert.equal((await db.doc(`telephones_valides/client_${TEL_AWA}`).get()).get('uid'), 'awa', 'le premier garde son numéro');
});

test('validation : revalider le même numéro est sans danger ; changer de numéro libère l\'ancien', async () => {
  await valider('awa');
  preuve = preuveDe(TEL_AWA, { connecteLe: apres(5 * MINUTE) });
  await valider('awa', apres(5 * MINUTE));
  assert.equal(((await profil()).telephoneVerifieLe as Timestamp).toMillis(), apres(5 * MINUTE).getTime());
  assert.equal((await db.collection('telephones_valides').get()).size, 1);

  // La personne change de numéro (profil), valide le nouveau : l'ancien est libéré.
  await db.doc('users/awa').update({ telephone: '76 234 56 78' });
  preuve = preuveDe(TEL_MOUSSA, { connecteLe: apres(8 * MINUTE) });
  await valider('awa', apres(8 * MINUTE));
  assert.equal((await profil()).telephoneValide, TEL_MOUSSA);
  assert.deepEqual((await db.collection('telephones_valides').get()).docs.map((d) => d.id), [`client_${TEL_MOUSSA}`]);
  await creerProfil('fatou', 'client', TEL_AWA);
  preuve = preuveDe(TEL_AWA, { uid: 'session-telephone-2', connecteLe: apres(11 * MINUTE) });
  await valider('fatou', apres(11 * MINUTE));
  assert.equal((await profil('fatou')).telephoneValide, TEL_AWA, 'l\'ancien numéro d\'Awa est de nouveau disponible');
});

test('validation : le numéro est celui du JETON, jamais celui de la demande ; un autre numéro que celui du compte est refusé', async () => {
  preuve = preuveDe(TEL_MOUSSA);
  const e = await refuse(valider('awa', t0, { jeton: JETON, telephone: TEL_AWA }), 'failed-precondition');
  assert.match(e.message, /pas celui de votre compte/);
  const p = await profil();
  assert.equal(p.telephoneVerifie, undefined);
  assert.equal((await db.collection('telephones_valides').get()).size, 0);
  assert.deepEqual(sessionsSupprimees, [], 'rien à nettoyer : la validation a échoué');
});

test('validation : jeton refusé, mauvais fournisseur, session du compte lui-même, numéro étranger, jeton trop vieux ou venu du futur', async () => {
  preuve = new Error('Firebase ID token has expired');
  await refuse(valider(), 'permission-denied');
  preuve = preuveDe(TEL_AWA, { fournisseur: 'password' });
  await refuse(valider(), 'permission-denied');
  preuve = preuveDe(TEL_AWA, { fournisseur: 'google.com' });
  await refuse(valider(), 'permission-denied');
  preuve = preuveDe(TEL_AWA, { uid: 'awa' });
  await refuse(valider(), 'permission-denied');
  preuve = preuveDe('+33612345678');
  await refuse(valider(), 'permission-denied');
  preuve = preuveDe(undefined);
  await refuse(valider(), 'permission-denied');
  preuve = preuveDe(TEL_AWA, { connecteLe: new Date(t0.getTime() - FRAICHEUR_CODE_MS - 1) });
  await refuse(valider(), 'permission-denied');
  preuve = preuveDe(TEL_AWA, { connecteLe: apres(3 * MINUTE) });
  await refuse(valider(), 'permission-denied');
  preuve = preuveDe(TEL_AWA, { connecteLe: undefined });
  await refuse(valider(), 'permission-denied');
  assert.equal((await profil()).telephoneVerifie, undefined, 'aucune de ces preuves ne marque le compte');

  // Limites incluses : tout juste assez frais, légèrement en avance (horloges non synchronisées).
  preuve = preuveDe(TEL_AWA, { connecteLe: new Date(t0.getTime() - FRAICHEUR_CODE_MS) });
  await valider();
  preuve = preuveDe(TEL_AWA, { connecteLe: apres(MINUTE) });
  await valider();
});

test('validation : réservée aux comptes Client et Chauffeur existants', async () => {
  await db.doc('users/chef').set({ role: 'admin', nom: 'Chef', email: 'chef@test.sn', telephone: TEL_AWA });
  await refuse(valider('chef'), 'permission-denied');
  await refuse(valider('inconnu'), 'permission-denied');
  assert.equal((await profil('chef')).telephoneVerifie, undefined);
  await refuse(validerSansConnexion(), 'unauthenticated');
});

test('validation : une panne du nettoyage de la session « téléphone » ne fait pas échouer la validation', async () => {
  suppressionEnPanne = true;
  assert.deepEqual(await valider(), { valide: true, telephone: TEL_AWA });
  assert.equal((await profil()).telephoneVerifie, true);
});

test('validation : ne touche ni au portefeuille, ni aux champs de paiement, ni à la marque « compte de test »', async () => {
  await db.doc('users/awa').update({ testeurOrangeMoney: true, statutCompte: 'actif' });
  await db.doc('portefeuilles/awa').set({ soldeFcfa: 2700, argentReelFcfa: 2700 });
  const avant = { profil: await profil(), portefeuille: (await db.doc('portefeuilles/awa').get()).data() };
  await valider();
  const p = await profil();
  const { telephoneVerifie, telephoneValide, telephoneVerifieLe, ...reste } = p;
  assert.ok(telephoneVerifie === true && telephoneValide && telephoneVerifieLe);
  assert.deepEqual(reste, avant.profil, 'tout le reste du profil est identique');
  assert.deepEqual((await db.doc('portefeuilles/awa').get()).data(), avant.portefeuille);
  assert.equal(p.testeurOrangeMoney, true);
});

// --- Bienvenue -------------------------------------------------------------------------------

const reglages = (extra: Record<string, unknown> = {}) => ({
  bienvenue: true, email: false, validation: 'fermee' as const, nouveauxComptesDepuis: OUVERTURE, ...extra,
});
const bienvenue = (uid = 'awa', extra: Record<string, unknown> = {}) =>
  declencherBienvenue(db, comptes, fcm, uid, t0, reglages(extra));
const bienvenueSansConnexion = () => declencherBienvenue(db, comptes, fcm, undefined, t0, reglages());
const jetonAppareil = (uid: string, id = `jeton-${uid}`) => db.doc(`appareils/${uid}/jetons/${id}`).set({ plateforme: 'android' });

test('bienvenue : un nouveau compte dont l\'e-mail est vérifié est accueilli UNE fois (marque, notification)', async () => {
  await jetonAppareil('awa');
  assert.deepEqual(await bienvenue(), { envoye: true, role: 'client' });
  assert.equal(((await profil()).bienvenueEnvoyeeLe as Timestamp).toMillis(), t0.getTime());
  assert.equal(fcm.envois.length, 1);
  assert.deepEqual(fcm.envois[0].jetons, ['jeton-awa']);
  const push = fcm.envois[0].push;
  assert.equal(push.titre, 'Bienvenue chez SPRINT');
  assert.match(push.corps, /commandez votre première course/);
  assert.equal(push.canal, 'messages');
  assert.equal(push.lien, LIENS.accueilClient);
  assert.deepEqual(push.donnees, { type: 'bienvenue' });
  assert.equal((await db.collection('mail').get()).size, 0, 'e-mail fermé : aucun document');

  assert.deepEqual(await bienvenue(), { envoye: false, raison: 'deja_envoye' });
  assert.equal(fcm.envois.length, 1, 'pas de seconde notification');
});

test('bienvenue : un chauffeur reçoit le texte du chauffeur et un lien vers son espace', async () => {
  await creerProfil('moussa', 'conducteur', TEL_MOUSSA, { prenom: 'Moussa' });
  await jetonAppareil('moussa');
  assert.deepEqual(await bienvenue('moussa'), { envoye: true, role: 'conducteur' });
  assert.match(fcm.envois[0].push.corps, /Complétez votre dossier/);
  assert.equal(fcm.envois[0].push.lien, LIENS.chauffeur);
});

test('bienvenue : l\'e-mail part du domaine officiel via la collection `mail`, au nom du compte et une seule fois', async () => {
  assert.deepEqual(await bienvenue('awa', { email: true }), { envoye: true, role: 'client' });
  const doc = await db.doc('mail/bienvenue_awa').get();
  assert.ok(doc.exists);
  assert.deepEqual(doc.get('to'), ['awa@test.sn']);
  assert.equal(doc.get('message.subject'), 'Bienvenue chez SPRINT');
  assert.match(doc.get('message.html'), /Bonjour Awa,/);
  assert.equal((await db.collection('mail').get()).size, 1);
  await bienvenue('awa', { email: true });
  assert.equal((await db.collection('mail').get()).size, 1);

  // Pas d'adresse connue : pas de courriel, mais la bienvenue (écran, notification) a lieu.
  await creerProfil('fatou', 'client', '75 111 22 33');
  compte = { ...compte, email: undefined };
  assert.equal((await bienvenue('fatou', { email: true })).envoye, true);
  assert.ok(!(await db.doc('mail/bienvenue_fatou').get()).exists);
});

test('bienvenue : deux appels en même temps n\'accueillent qu\'une fois', async () => {
  await jetonAppareil('awa');
  const reponses = await Promise.all([bienvenue(), bienvenue(), bienvenue()]);
  assert.equal(reponses.filter((r) => r.envoye).length, 1);
  assert.equal(fcm.envois.length, 1);
});

test('bienvenue : rien pour un compte ancien, un e-mail non vérifié, un rôle sans espace public ou un profil absent', async () => {
  compte = { ...compte, creeLe: new Date(OUVERTURE.getTime() - 1) };
  assert.deepEqual(await bienvenue(), { envoye: false, raison: 'compte_ancien' });
  compte = { ...compte, creeLe: null };
  assert.deepEqual(await bienvenue(), { envoye: false, raison: 'compte_ancien' });
  compte = { creeLe: OUVERTURE, emailVerifie: false, email: 'awa@test.sn' };
  assert.deepEqual(await bienvenue(), { envoye: false, raison: 'email_non_verifie' });
  compte = { creeLe: OUVERTURE, emailVerifie: true, email: 'chef@test.sn' };
  await db.doc('users/chef').set({ role: 'admin', nom: 'Chef' });
  assert.deepEqual(await bienvenue('chef'), { envoye: false, raison: 'role' });
  assert.deepEqual(await bienvenue('inconnu'), { envoye: false, raison: 'role' });
  assert.equal((await profil()).bienvenueEnvoyeeLe, undefined);
  assert.equal(fcm.envois.length, 0);
  await refuse(bienvenueSansConnexion(), 'unauthenticated');
});

test('bienvenue : le compte créé à l\'instant même de l\'ouverture est accueilli (borne incluse)', async () => {
  compte = { ...compte, creeLe: OUVERTURE };
  assert.equal((await bienvenue()).envoye, true);
});

test('bienvenue : quand le numéro est OBLIGATOIRE, elle attend qu\'il soit validé (et qu\'il le reste) ; facultatif ou fermé : elle n\'attend rien', async () => {
  assert.deepEqual(await bienvenue('awa', { validation: 'obligatoire' }), { envoye: false, raison: 'telephone_non_valide' });
  assert.equal((await profil()).bienvenueEnvoyeeLe, undefined);

  // Numéro modifié après validation : plus validé.
  await valider();
  await db.doc('users/awa').update({ telephone: '76 234 56 78' });
  assert.equal((await bienvenue('awa', { validation: 'obligatoire' })).raison, 'telephone_non_valide');

  await db.doc('users/awa').update({ telephone: '77 123 45 67' });
  assert.equal((await bienvenue('awa', { validation: 'obligatoire' })).envoye, true);

  await creerProfil('fatou', 'client', '75 111 22 33');
  assert.equal((await bienvenue('fatou', { validation: 'facultative' })).envoye, true);
  await creerProfil('ibou', 'client', '70 111 22 33');
  assert.equal((await bienvenue('ibou', { validation: 'fermee' })).envoye, true);
});

test('bienvenue : sans appareil enregistré, ou notification en panne, la bienvenue a lieu quand même (l\'écran suffit)', async () => {
  assert.equal((await bienvenue()).envoye, true);
  assert.equal(fcm.envois.length, 0);
  await creerProfil('fatou', 'client', '75 111 22 33');
  await jetonAppareil('fatou');
  fcm.enPanne = true;
  assert.equal((await bienvenue('fatou')).envoye, true);
  assert.ok((await profil('fatou')).bienvenueEnvoyeeLe, 'marquée : pas de seconde tentative');
});

test('bienvenue : ne touche ni au portefeuille ni aux champs de paiement ni à la marque « compte de test »', async () => {
  await db.doc('users/awa').update({ testeurOrangeMoney: true });
  await db.doc('portefeuilles/awa').set({ soldeFcfa: 500, argentReelFcfa: 500 });
  const avant = await profil();
  await bienvenue();
  const { bienvenueEnvoyeeLe, ...reste } = await profil();
  assert.ok(bienvenueEnvoyeeLe);
  assert.deepEqual(reste, avant);
  assert.deepEqual((await db.doc('portefeuilles/awa').get()).data(), { soldeFcfa: 500, argentReelFcfa: 500 });
});

// --- Vrai parcours par téléphone dans l'émulateur Auth -----------------------------------------

/** Ce que fait le SDK de l'app : demande du code, lecture du SMS (fourni par l'émulateur), connexion. */
async function connexionParTelephone(numero: string): Promise<{ idToken: string; localId: string }> {
  const hote = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  assert.ok(hote, 'l\'émulateur Auth doit tourner (npm run test:emulateur)');
  const base = `http://${hote}/identitytoolkit.googleapis.com/v1`;
  const post = async (chemin: string, corps: unknown) => {
    const reponse = await fetch(`${base}/${chemin}?key=fausse-cle`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corps),
    });
    assert.equal(reponse.ok, true, `${chemin} : ${reponse.status} ${await reponse.clone().text()}`);
    return (await reponse.json()) as Record<string, string>;
  };
  const { sessionInfo } = await post('accounts:sendVerificationCode', { phoneNumber: numero, recaptchaToken: 'jeton-de-test' });
  const sms = (await (await fetch(`http://${hote}/emulator/v1/projects/demo-sprint/verificationCodes`)).json()) as {
    verificationCodes: { sessionInfo: string; code: string }[];
  };
  const code = sms.verificationCodes.find((c) => c.sessionInfo === sessionInfo)?.code;
  assert.ok(code, 'code SMS introuvable dans l\'émulateur');
  return (await post('accounts:signInWithPhoneNumber', { sessionInfo, code })) as { idToken: string; localId: string };
}

test('émulateur Auth : le vrai vérificateur lit le jeton d\'une connexion par téléphone (fournisseur, numéro, heure)', async () => {
  const { idToken, localId } = await connexionParTelephone(TEL_AWA);
  const lu = await verifierJetonFirebase(idToken);
  assert.equal(lu.uid, localId);
  assert.equal(lu.fournisseur, 'phone');
  assert.equal(lu.telephone, TEL_AWA);
  assert.ok(lu.connecteLe && Math.abs(Date.now() - lu.connecteLe.getTime()) < 2 * MINUTE, `heure : ${lu.connecteLe?.toISOString()}`);
  await assert.rejects(verifierJetonFirebase('pas-un-jeton'));
});

test('émulateur Auth : validation de bout en bout avec les vrais accès, puis la session « téléphone » est supprimée', async () => {
  const { idToken, localId } = await connexionParTelephone(TEL_AWA);
  assert.ok(await getAuth().getUser(localId), 'la session « téléphone » existe avant');
  const resultat = await validerTelephone(db, verifierJetonFirebase, new ComptesFirebase(), 'awa', { jeton: idToken }, new Date(), 'obligatoire');
  assert.deepEqual(resultat, { valide: true, telephone: TEL_AWA });
  assert.equal((await profil()).telephoneValide, TEL_AWA);
  await assert.rejects(getAuth().getUser(localId), /no user record|user-not-found/i, 'session supprimée');
});

test('émulateur Auth : jamais la suppression d\'un vrai compte (e-mail), même si son jeton est présenté', async () => {
  const reel = await getAuth().createUser({ email: 'vrai@test.sn', password: 'mot-de-passe-vrai', emailVerified: true });
  const comptesReels = new ComptesFirebase();
  assert.equal(await comptesReels.supprimerSessionTelephone(reel.uid), false);
  assert.equal((await getAuth().getUser(reel.uid)).email, 'vrai@test.sn');

  // Session « téléphone » à laquelle un e-mail a été relié : c'est devenu un vrai compte.
  const { localId } = await connexionParTelephone('+221751112233');
  await getAuth().updateUser(localId, { email: 'lie@test.sn' });
  assert.equal(await comptesReels.supprimerSessionTelephone(localId), false);
  assert.ok(await getAuth().getUser(localId));

  // Un compte e-mail n'a pas de fournisseur « phone » : son jeton ne valide aucun numéro.
  const compteEmail = await comptesReels.lire(reel.uid);
  assert.equal(compteEmail.emailVerifie, true);
  assert.ok(compteEmail.creeLe instanceof Date && !Number.isNaN(compteEmail.creeLe.getTime()));
});
