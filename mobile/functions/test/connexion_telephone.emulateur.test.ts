// Connexion par téléphone et annuaire côté serveur, sur les émulateurs
// Firestore et Auth : npm run test:emulateur.
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import {
  cleLimiteAdresse,
  cleLimiteNumero,
  connexionTelephone,
  DUREE_MIN_ECHEC_MS,
  LIMITE_ADRESSE,
  LIMITE_TELEPHONE,
  MESSAGE_IDENTIFIANTS,
  synchroniserAnnuaire,
  verifierMotDePasseFirebase,
  type ResultatMotDePasse,
  type VerifierMotDePasse,
} from '../src/connexion_telephone';

const t0 = new Date(Date.UTC(2026, 9, 8, 12));
const apres = (ms: number) => new Date(t0.getTime() + ms);
const MINUTE = 60_000;

const TEL_AWA = '+221771111111';
const TEL_MOUSSA = '+221772222222';
const IP = '41.82.10.5';

let app: App;
let db: Firestore;

/** Vérificateur factice : mots de passe par e-mail ; compte ses appels. */
let appelsVerif: { email: string; motDePasse: string }[];
let modeVerif: ResultatMotDePasse | null;
const MOTS_DE_PASSE: Record<string, string> = { 'awa@test.sn': 'motdepasse-awa', 'moussa@test.sn': 'motdepasse-moussa' };
const verifier: VerifierMotDePasse = async (email, motDePasse) => {
  appelsVerif.push({ email, motDePasse });
  if (modeVerif) return modeVerif;
  return MOTS_DE_PASSE[email] === motDePasse ? 'ok' : 'refuse';
};

let pauses: number[];
const dormir = async (ms: number) => void pauses.push(ms);
/** Horloge figée : tout refus doit alors « dormir » la durée minimale. */
const horlogeFigee = () => 0;

const connexion = (donnees: unknown, quand = t0, adresse: string | undefined = IP) =>
  connexionTelephone(db, verifier, { adresse }, donnees, quand, dormir, horlogeFigee);
const essai = (extra: Record<string, unknown> = {}) => ({ role: 'client', telephone: TEL_AWA, motDePasse: 'motdepasse-awa', ...extra });

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' }, 'connexion-telephone');
  db = getFirestore(app);
});

after(() => deleteApp(app));

beforeEach(async () => {
  appelsVerif = [];
  modeVerif = null;
  pauses = [];
  for (const nom of ['users', 'annuaire_telephones', 'limites_connexion']) {
    const docs = await db.collection(nom).listDocuments();
    await Promise.all(docs.map((d) => d.delete()));
  }
  await db.doc(`annuaire_telephones/client_${TEL_AWA}`).set({ uid: 'awa', email: 'awa@test.sn' });
  await db.doc(`annuaire_telephones/conducteur_${TEL_MOUSSA}`).set({ uid: 'moussa', email: 'moussa@test.sn' });
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

const compteur = async (cle: string) => (await db.doc(`limites_connexion/${cle}`).get()).data();

// --- Connexion ------------------------------------------------------------------

test('bon mot de passe : l\'e-mail est rendu, sans aucune pause ni compteur', async () => {
  assert.deepEqual(await connexion(essai()), { email: 'awa@test.sn' });
  assert.deepEqual(pauses, []);
  assert.equal(await compteur(cleLimiteNumero('client', TEL_AWA)), undefined);
  assert.deepEqual(appelsVerif, [{ email: 'awa@test.sn', motDePasse: 'motdepasse-awa' }]);
});

test('numéro avec espaces autour : même compte', async () => {
  assert.deepEqual(await connexion(essai({ telephone: `  ${TEL_AWA}  ` })), { email: 'awa@test.sn' });
});

test('mot de passe faux : refus générique, au moins la durée minimale, échec compté', async () => {
  const e = await refuse(connexion(essai({ motDePasse: 'mauvais' })), 'permission-denied');
  assert.equal(e.message, MESSAGE_IDENTIFIANTS);
  assert.deepEqual(pauses, [DUREE_MIN_ECHEC_MS]);
  assert.equal((await compteur(cleLimiteNumero('client', TEL_AWA)))?.echecs, 1);
  assert.equal((await compteur(cleLimiteAdresse(IP)))?.echecs, 1);
});

test('numéro inconnu et mot de passe faux : exactement la même réponse (aucun moyen de savoir qui a un compte)', async () => {
  const faux = await refuse(connexion(essai({ motDePasse: 'mauvais' })), 'permission-denied');
  const inconnu = await refuse(connexion(essai({ telephone: '+221700000000' })), 'permission-denied');
  assert.equal(inconnu.message, faux.message);
  assert.deepEqual(inconnu.details, faux.details);
  assert.deepEqual(pauses, [DUREE_MIN_ECHEC_MS, DUREE_MIN_ECHEC_MS]);
  // Le numéro inconnu n'a même pas été présenté à Firebase.
  assert.equal(appelsVerif.length, 1);
});

test('numéro inutilisable (barre oblique, trop long) : refus générique, jamais d\'erreur technique', async () => {
  for (const telephone of ['77/123', '7'.repeat(41), '   ']) {
    const e = await refuse(connexion(essai({ telephone })), 'permission-denied');
    assert.equal(e.message, MESSAGE_IDENTIFIANTS);
  }
  assert.equal(appelsVerif.length, 0);
});

test('rôles étanches : le numéro d\'un client ne connecte pas un conducteur (et inversement)', async () => {
  await refuse(connexion(essai({ role: 'conducteur' })), 'permission-denied');
  await refuse(connexion(essai({ role: 'client', telephone: TEL_MOUSSA, motDePasse: 'motdepasse-moussa' })), 'permission-denied');
  assert.deepEqual(await connexion(essai({ role: 'conducteur', telephone: TEL_MOUSSA, motDePasse: 'motdepasse-moussa' })), {
    email: 'moussa@test.sn',
  });
});

test('5 échecs bloquent le numéro 15 minutes, même avec le bon mot de passe, puis la porte se rouvre', async () => {
  for (let i = 0; i < LIMITE_TELEPHONE.seuil; i++) {
    await refuse(connexion(essai({ motDePasse: 'mauvais' }), apres(i * 1000)), 'permission-denied');
  }
  const avant = appelsVerif.length;
  const bloque = await refuse(connexion(essai(), apres(10_000)), 'resource-exhausted');
  assert.match(bloque.message, /Trop de tentatives/);
  assert.equal(appelsVerif.length, avant, 'le mot de passe n\'est même pas examiné pendant le blocage');
  // Toujours bloqué juste avant la fin, libre juste après.
  await refuse(connexion(essai(), apres(4_000 + 15 * MINUTE - 1)), 'resource-exhausted');
  assert.deepEqual(await connexion(essai(), apres(4_000 + 15 * MINUTE + 1)), { email: 'awa@test.sn' });
});

test('un numéro inconnu se bloque exactement comme un numéro connu (le blocage ne trahit rien)', async () => {
  for (let i = 0; i < LIMITE_TELEPHONE.seuil; i++) {
    await refuse(connexion(essai({ telephone: '+221700000000' }), apres(i * 1000)), 'permission-denied');
  }
  const bloque = await refuse(connexion(essai({ telephone: '+221700000000' }), apres(10_000)), 'resource-exhausted');
  assert.match(bloque.message, /Trop de tentatives/);
});

test('échecs espacés de plus de 15 minutes : le compteur repart de zéro', async () => {
  for (let i = 0; i < LIMITE_TELEPHONE.seuil - 1; i++) {
    await refuse(connexion(essai({ motDePasse: 'mauvais' }), apres(i * 1000)), 'permission-denied');
  }
  await refuse(connexion(essai({ motDePasse: 'mauvais' }), apres(16 * MINUTE)), 'permission-denied');
  assert.equal((await compteur(cleLimiteNumero('client', TEL_AWA)))?.echecs, 1);
  assert.deepEqual(await connexion(essai(), apres(17 * MINUTE)), { email: 'awa@test.sn' });
});

test('une connexion réussie remet le compteur du numéro à zéro', async () => {
  for (let i = 0; i < LIMITE_TELEPHONE.seuil - 1; i++) {
    await refuse(connexion(essai({ motDePasse: 'mauvais' }), apres(i * 1000)), 'permission-denied');
  }
  await connexion(essai(), apres(5_000));
  assert.equal(await compteur(cleLimiteNumero('client', TEL_AWA)), undefined);
  for (let i = 0; i < LIMITE_TELEPHONE.seuil - 1; i++) {
    await refuse(connexion(essai({ motDePasse: 'mauvais' }), apres(6_000 + i * 1000)), 'permission-denied');
  }
  assert.deepEqual(await connexion(essai(), apres(20_000)), { email: 'awa@test.sn' });
});

test('adresse réseau : au-delà du seuil, tous ses essais sont refusés, les autres adresses non', async () => {
  await db.doc(`limites_connexion/${cleLimiteAdresse(IP)}`).set({
    echecs: LIMITE_ADRESSE.seuil - 1,
    debutLe: Timestamp.fromDate(t0),
    expireLe: Timestamp.fromDate(apres(24 * 60 * MINUTE)),
  });
  await refuse(connexion(essai({ motDePasse: 'mauvais' })), 'permission-denied'); // le 100e échec
  await refuse(connexion(essai(), apres(1000)), 'resource-exhausted');
  await refuse(connexion(essai({ role: 'conducteur', telephone: TEL_MOUSSA, motDePasse: 'motdepasse-moussa' }), apres(1000)), 'resource-exhausted');
  assert.deepEqual(await connexion(essai(), apres(1000), '41.82.10.99'), { email: 'awa@test.sn' });
});

test('Firebase indisponible ou qui freine le compte : message à part, et ce n\'est pas compté comme un échec', async () => {
  modeVerif = 'indisponible';
  const panne = await refuse(connexion(essai()), 'unavailable');
  assert.match(panne.message, /momentanément indisponible/);
  modeVerif = 'limite';
  const frein = await refuse(connexion(essai()), 'resource-exhausted');
  assert.match(frein.message, /Trop de tentatives/);
  assert.equal(await compteur(cleLimiteNumero('client', TEL_AWA)), undefined);
});

test('demande mal formée : refusée tout de suite, rien de compté ni examiné', async () => {
  const mauvaises: unknown[] = [
    undefined,
    null,
    'texte',
    {},
    essai({ role: 'admin' }),
    essai({ role: undefined }),
    essai({ telephone: 771111111 }),
    essai({ motDePasse: '' }),
    essai({ motDePasse: 12345 }),
    essai({ motDePasse: 'x'.repeat(4097) }),
    essai({ telephone: 'x'.repeat(161) }),
  ];
  for (const donnees of mauvaises) await refuse(connexion(donnees), 'invalid-argument');
  assert.equal(appelsVerif.length, 0);
  assert.equal((await db.collection('limites_connexion').get()).size, 0);
  assert.deepEqual(pauses, []);
});

test('les compteurs ne contiennent ni numéro, ni adresse, ni mot de passe', async () => {
  await refuse(connexion(essai({ motDePasse: 'secret-tres-particulier' })), 'permission-denied');
  const docs = await db.collection('limites_connexion').get();
  assert.equal(docs.size, 2);
  const tout = JSON.stringify(docs.docs.map((d) => ({ id: d.id, ...d.data() })));
  for (const interdit of [TEL_AWA, '771111111', IP, 'secret-tres-particulier']) assert.ok(!tout.includes(interdit), interdit);
  for (const d of docs.docs) assert.match(d.id, /^(tel|ip)_[0-9a-f]{40}$/);
});

// --- Annuaire côté serveur --------------------------------------------------------

const profil = (uid: string, role: string, telephone?: unknown) =>
  db.doc(`users/${uid}`).set({ role, nom: uid, ...(telephone === undefined ? {} : { telephone }) });
const entrees = async () => Object.fromEntries((await db.collection('annuaire_telephones').get()).docs.map((d) => [d.id, d.data()]));

test('annuaire : l\'entrée est publiée d\'après le profil, une seule fois, e-mail du jeton', async () => {
  await profil('fatou', 'client', '+221773333333');
  assert.deepEqual(await synchroniserAnnuaire(db, 'fatou', 'fatou@test.sn'), { publie: true });
  assert.deepEqual((await entrees())['client_+221773333333'], { uid: 'fatou', email: 'fatou@test.sn' });
  assert.deepEqual(await synchroniserAnnuaire(db, 'fatou', 'fatou@test.sn'), { publie: true });
  assert.equal(Object.keys(await entrees()).length, 3);
});

test('annuaire : un numéro déjà pris par un autre compte n\'est jamais écrasé', async () => {
  await profil('intrus', 'client', TEL_AWA);
  assert.deepEqual(await synchroniserAnnuaire(db, 'intrus', 'intrus@test.sn'), { publie: false });
  assert.deepEqual((await entrees())[`client_${TEL_AWA}`], { uid: 'awa', email: 'awa@test.sn' });
});

test('annuaire : numéro changé, l\'ancien ne permet plus de se connecter', async () => {
  await profil('awa', 'client', '+221774444444');
  assert.deepEqual(await synchroniserAnnuaire(db, 'awa', 'awa@test.sn'), { publie: true });
  const apresChangement = await entrees();
  assert.equal(apresChangement[`client_${TEL_AWA}`], undefined);
  assert.deepEqual(apresChangement['client_+221774444444'], { uid: 'awa', email: 'awa@test.sn' });
  assert.deepEqual(apresChangement[`conducteur_${TEL_MOUSSA}`], { uid: 'moussa', email: 'moussa@test.sn' });
  await refuse(connexion(essai()), 'permission-denied'); // l'ancien numéro ne connecte plus
});

test('annuaire : nouveau numéro pris par un autre, l\'ancien est retiré quand même', async () => {
  await profil('awa', 'client', TEL_MOUSSA);
  await db.doc(`annuaire_telephones/client_${TEL_MOUSSA}`).set({ uid: 'moussa', email: 'moussa@test.sn' });
  assert.deepEqual(await synchroniserAnnuaire(db, 'awa', 'awa@test.sn'), { publie: false });
  const e = await entrees();
  assert.equal(e[`client_${TEL_AWA}`], undefined);
  assert.deepEqual(e[`client_${TEL_MOUSSA}`], { uid: 'moussa', email: 'moussa@test.sn' });
});

test('annuaire : profil sans numéro valable, ou rôle autre que client/conducteur : rien de publié', async () => {
  await profil('chef', 'admin', '+221775555555');
  await profil('sansnumero', 'client', undefined);
  await profil('barre', 'client', '77/123');
  await profil('nombre', 'client', 771111111);
  for (const uid of ['chef', 'sansnumero', 'barre', 'nombre', 'inconnu']) {
    assert.deepEqual(await synchroniserAnnuaire(db, uid, `${uid}@test.sn`), { publie: false }, uid);
  }
  assert.equal(Object.keys(await entrees()).length, 2);
});

test('annuaire : connexion et e-mail exigés', async () => {
  await refuse(synchroniserAnnuaire(db, undefined, 'x@test.sn'), 'unauthenticated');
  await refuse(synchroniserAnnuaire(db, 'awa', undefined), 'failed-precondition');
});

// --- Vraie vérification, contre l'émulateur Firebase Auth -------------------------

test('émulateur Auth : le vrai vérificateur accepte le bon mot de passe et refuse le reste', async () => {
  assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST, 'l\'émulateur Auth doit tourner (npm run test:emulateur)');
  await getAuth(app).createUser({ email: 'reel@test.sn', password: 'vrai-mot-de-passe', emailVerified: false });
  const reel = verifierMotDePasseFirebase('cle-de-test');
  assert.equal(await reel('reel@test.sn', 'vrai-mot-de-passe'), 'ok');
  assert.equal(await reel('reel@test.sn', 'faux-mot-de-passe'), 'refuse');
  assert.equal(await reel('inconnu@test.sn', 'vrai-mot-de-passe'), 'refuse');
  assert.equal(await reel('pas-un-email', 'vrai-mot-de-passe'), 'refuse');
});

test('émulateur Auth : parcours complet par téléphone avec le vrai vérificateur', async () => {
  await getAuth(app).createUser({ email: 'complet@test.sn', password: 'mot-de-passe-complet' });
  await db.doc('annuaire_telephones/client_+221776666666').set({ uid: 'complet', email: 'complet@test.sn' });
  const reel = verifierMotDePasseFirebase('cle-de-test');
  const appeler = (motDePasse: string) =>
    connexionTelephone(db, reel, { adresse: IP }, { role: 'client', telephone: '+221776666666', motDePasse }, t0, dormir, horlogeFigee);

  assert.deepEqual(await appeler('mot-de-passe-complet'), { email: 'complet@test.sn' });
  const e = await refuse(appeler('pas-le-bon'), 'permission-denied');
  assert.equal(e.message, MESSAGE_IDENTIFIANTS);
});
