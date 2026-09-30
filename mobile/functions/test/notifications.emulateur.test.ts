// Notifications push sur l'émulateur Firestore : npm run test:emulateur.
// L'envoi réel (Firebase Cloud Messaging) est remplacé par un faux qui
// enregistre ce qui serait envoyé.
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { FournisseurSimule } from '../src/fournisseurs';
import {
  LIENS,
  LONGUEUR_MAX_TEXTE,
  SITE,
  MAX_CHAUFFEURS_PREVENUS,
  notifierAcceptation,
  notifierMessage,
  notifierNouvelleCourse,
  type EnvoiPush,
  type Messagerie,
} from '../src/notifications';
import { annulerCourse, surveiller, traiterEvenement } from '../src/paiements';

const midi = new Date(Date.UTC(2026, 8, 29, 12));
const secondes = (n: number) => new Date(midi.getTime() + n * 1000);

let app: App;
let db: Firestore;

interface Envoi {
  jetons: string[];
  push: EnvoiPush;
}
class MessagerieFausse implements Messagerie {
  envois: Envoi[] = [];
  jetonsMorts = new Set<string>();
  enPanne = false;

  async envoyer(jetons: string[], push: EnvoiPush) {
    if (this.enPanne) throw new Error('FCM indisponible');
    this.envois.push({ jetons: [...jetons], push });
    return { envoyes: jetons.filter((j) => !this.jetonsMorts.has(j)).length, invalides: jetons.filter((j) => this.jetonsMorts.has(j)) };
  }
}
let fcm: MessagerieFausse;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' }, 'notifications');
  db = getFirestore(app);
});
after(() => deleteApp(app));

async function vider() {
  for (const nom of ['users', 'courses', 'commandes', 'chats', 'appareils', 'profils_publics']) {
    await db.recursiveDelete(db.collection(nom));
  }
}

const jeton = (uid: string, id: string) => db.doc(`appareils/${uid}/jetons/${id}`).set({ plateforme: 'android' });

async function ecrireMessage(chatId: string, id: string, expediteur: string, texte: string, quand = midi) {
  await db.doc(`chats/${chatId}/messages/${id}`).set({ senderId: expediteur, text: texte, timestamp: Timestamp.fromDate(quand) });
}

async function courseActive(statut = 'acceptee', extra: Record<string, unknown> = {}) {
  await db.doc('courses/c1').set({
    clientId: 'awa', chauffeurId: 'moussa', statut, type: 'PASSAGER',
    adresseDepart: 'Plateau', adresseArrivee: 'Almadies', prixFcfa: 2300, commandeId: 'cmd1', ...extra,
  });
}

beforeEach(async () => {
  await vider();
  fcm = new MessagerieFausse();
  await db.doc('profils_publics/moussa').set({ nom: 'Moussa Diop', vehiculeId: 'Honda CB125 (2021)', plaqueImmatriculation: 'DK-4821-AB' });
  await db.doc('profils_publics/awa').set({ nom: 'Awa Ndiaye' });
  await jeton('awa', 'jetonAwa');
  await jeton('moussa', 'jetonMoussa');
});

const refuse = async (p: Promise<unknown>, code: string) => {
  await assert.rejects(p, (e) => e instanceof HttpsError && e.code === code);
};

// ---------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------

test('message du chauffeur : le client reçoit son nom et le texte, une seule fois', async () => {
  await courseActive();
  await ecrireMessage('awa_moussa', 'm1', 'moussa', 'Je suis devant la pharmacie');
  const r = await notifierMessage(db, fcm, 'moussa', { messageId: 'm1', destinataireId: 'awa' }, secondes(5));
  assert.deepEqual(r, { envoye: true });
  assert.equal(fcm.envois.length, 1);
  assert.deepEqual(fcm.envois[0].jetons, ['jetonAwa']);
  assert.equal(fcm.envois[0].push.titre, 'Moussa Diop');
  assert.equal(fcm.envois[0].push.corps, 'Je suis devant la pharmacie');
  assert.equal(fcm.envois[0].push.canal, 'messages');
  assert.deepEqual(fcm.envois[0].push.donnees, { type: 'message', expediteurId: 'moussa', courseId: 'c1' });
  // Sur le site, l'appui mène à la messagerie du client.
  assert.equal(fcm.envois[0].push.lien, LIENS.messagesClient);

  // Rejouer l'appel ne refait pas sonner le téléphone.
  const encore = await notifierMessage(db, fcm, 'moussa', { messageId: 'm1', destinataireId: 'awa' }, secondes(6));
  assert.deepEqual(encore, { envoye: false, raison: 'deja_notifie' });
  assert.equal(fcm.envois.length, 1);
});

test('message du client : le chauffeur est prévenu (sans nom public : « Votre client »)', async () => {
  await courseActive('en_cours');
  await db.doc('profils_publics/awa').delete();
  await ecrireMessage('awa_moussa', 'm1', 'awa', 'Je descends');
  await notifierMessage(db, fcm, 'awa', { messageId: 'm1', destinataireId: 'moussa' }, secondes(1));
  assert.deepEqual(fcm.envois[0].jetons, ['jetonMoussa']);
  assert.equal(fcm.envois[0].push.titre, 'Votre client');
  // Le destinataire est le chauffeur : son appui mène à son tableau de bord.
  assert.equal(fcm.envois[0].push.lien, LIENS.chauffeur);
});

test('le texte vient du message enregistré, jamais de l\'appelant ; long texte raccourci', async () => {
  await courseActive();
  await ecrireMessage('awa_moussa', 'm1', 'moussa', 'x'.repeat(LONGUEUR_MAX_TEXTE + 100));
  await notifierMessage(db, fcm, 'moussa', { messageId: 'm1', destinataireId: 'awa', texte: 'Cliquez ici : hameçon', titre: 'Sprint' }, secondes(1));
  const { corps, titre } = fcm.envois[0].push;
  assert.equal(titre, 'Moussa Diop');
  assert.ok(!corps.includes('hameçon'));
  assert.equal(corps.length, LONGUEUR_MAX_TEXTE);
  assert.ok(corps.endsWith('…'));
});

test('refusé : non connecté, identifiants invalides, message d\'un autre, sans course en cours', async () => {
  await courseActive();
  await ecrireMessage('awa_moussa', 'm1', 'awa', 'Bonjour');
  await refuse(notifierMessage(db, fcm, undefined, { messageId: 'm1', destinataireId: 'moussa' }, secondes(1)), 'unauthenticated');
  await refuse(notifierMessage(db, fcm, 'awa', { messageId: '../x', destinataireId: 'moussa' }, secondes(1)), 'invalid-argument');
  await refuse(notifierMessage(db, fcm, 'awa', { messageId: 'm1' }, secondes(1)), 'invalid-argument');
  await refuse(notifierMessage(db, fcm, 'awa', { messageId: 'm1', destinataireId: 'awa' }, secondes(1)), 'invalid-argument');
  await refuse(notifierMessage(db, fcm, 'awa', { messageId: 'absent', destinataireId: 'moussa' }, secondes(1)), 'not-found');
  // Le chauffeur essaie de faire notifier le message de la cliente : pas le sien.
  await refuse(notifierMessage(db, fcm, 'moussa', { messageId: 'm1', destinataireId: 'awa' }, secondes(1)), 'permission-denied');

  // Course terminée : plus personne à qui écrire.
  await db.doc('courses/c1').update({ statut: 'terminee' });
  await refuse(notifierMessage(db, fcm, 'awa', { messageId: 'm1', destinataireId: 'moussa' }, secondes(1)), 'permission-denied');
  assert.equal(fcm.envois.length, 0);
});

test('un tiers ne peut pas faire sonner le téléphone d\'un inconnu', async () => {
  await courseActive();
  await jeton('fatou', 'jetonFatou');
  await ecrireMessage('awa_fatou', 'm9', 'awa', 'Coucou'); // chat sans course entre les deux
  await refuse(notifierMessage(db, fcm, 'awa', { messageId: 'm9', destinataireId: 'fatou' }, secondes(1)), 'permission-denied');
  assert.equal(fcm.envois.length, 0);
});

test('message trop ancien : pas de notification tardive', async () => {
  await courseActive();
  await ecrireMessage('awa_moussa', 'm1', 'moussa', 'Ancien', new Date(midi.getTime() - 10 * 60_000));
  const r = await notifierMessage(db, fcm, 'moussa', { messageId: 'm1', destinataireId: 'awa' }, midi);
  assert.deepEqual(r, { envoye: false, raison: 'trop_ancien' });
  assert.equal(fcm.envois.length, 0);
});

test('jetons morts supprimés, jetons vivants conservés ; panne FCM sans erreur', async () => {
  await courseActive();
  await jeton('awa', 'jetonMort');
  fcm.jetonsMorts.add('jetonMort');
  await ecrireMessage('awa_moussa', 'm1', 'moussa', 'Salut');
  const r = await notifierMessage(db, fcm, 'moussa', { messageId: 'm1', destinataireId: 'awa' }, secondes(1));
  assert.equal(r.envoye, true);
  const restants = (await db.collection('appareils/awa/jetons').get()).docs.map((d) => d.id).sort();
  assert.deepEqual(restants, ['jetonAwa']);

  await ecrireMessage('awa_moussa', 'm2', 'moussa', 'Encore');
  fcm.enPanne = true;
  const panne = await notifierMessage(db, fcm, 'moussa', { messageId: 'm2', destinataireId: 'awa' }, secondes(2));
  assert.deepEqual(panne, { envoye: false });
});

test('destinataire sans appareil enregistré : rien d\'envoyé, pas d\'erreur', async () => {
  await courseActive();
  await db.recursiveDelete(db.collection('appareils'));
  await ecrireMessage('awa_moussa', 'm1', 'moussa', 'Salut');
  const r = await notifierMessage(db, fcm, 'moussa', { messageId: 'm1', destinataireId: 'awa' }, secondes(1));
  assert.deepEqual(r, { envoye: false });
  assert.equal(fcm.envois.length, 0);
});

// ---------------------------------------------------------------------
// Acceptation
// ---------------------------------------------------------------------

test('course acceptée : le client apprend qui vient (nom, moto, plaque), une seule fois', async () => {
  await courseActive();
  const r = await notifierAcceptation(db, fcm, 'moussa', { courseId: 'c1' }, secondes(1));
  assert.deepEqual(r, { envoye: true });
  const { push, jetons } = fcm.envois[0];
  assert.deepEqual(jetons, ['jetonAwa']);
  assert.equal(push.titre, 'Chauffeur trouvé !');
  assert.equal(push.corps, 'Moussa Diop arrive · Honda CB125 (2021) · DK-4821-AB');
  assert.equal(push.canal, 'courses');
  assert.deepEqual(push.donnees, { type: 'acceptee', courseId: 'c1' });
  assert.equal(push.lien, LIENS.activiteClient);

  assert.deepEqual(await notifierAcceptation(db, fcm, 'moussa', { courseId: 'c1' }, secondes(2)), { envoye: false, raison: 'deja_notifie' });
  assert.equal(fcm.envois.length, 1);
});

test('acceptation : seul le chauffeur de la course, et seulement tant qu\'elle est en cours', async () => {
  await courseActive();
  await refuse(notifierAcceptation(db, fcm, undefined, { courseId: 'c1' }, midi), 'unauthenticated');
  await refuse(notifierAcceptation(db, fcm, 'awa', { courseId: 'c1' }, midi), 'permission-denied');
  await refuse(notifierAcceptation(db, fcm, 'intrus', { courseId: 'c1' }, midi), 'permission-denied');
  await refuse(notifierAcceptation(db, fcm, 'moussa', { courseId: 'absente' }, midi), 'not-found');
  await refuse(notifierAcceptation(db, fcm, 'moussa', { courseId: 'a/b' }, midi), 'invalid-argument');
  await db.doc('courses/c1').update({ statut: 'terminee' });
  await refuse(notifierAcceptation(db, fcm, 'moussa', { courseId: 'c1' }, midi), 'failed-precondition');
  assert.equal(fcm.envois.length, 0);
});

// ---------------------------------------------------------------------
// Nouvelle course
// ---------------------------------------------------------------------

async function chauffeur(uid: string, extra: Record<string, unknown> = {}, avecJeton = true) {
  await db.doc(`users/${uid}`).set({ role: 'conducteur', statut: 'EN_LIGNE', statutValidation: 'valide', ...extra });
  if (avecJeton) await jeton(uid, `jeton_${uid}`);
}

test('nouvelle course : seuls les chauffeurs en ligne, validés, non sanctionnés et libres sont prévenus', async () => {
  await db.doc('courses/nouvelle').set({
    clientId: 'awa', chauffeurId: null, statut: 'en_attente', type: 'PASSAGER',
    adresseDepart: 'Plateau', adresseArrivee: 'Almadies', prixFcfa: 2300,
  });
  await chauffeur('libre1');
  await chauffeur('libre2');
  await chauffeur('horsLigne', { statut: 'HORS_LIGNE' });
  await chauffeur('nonValide', { statutValidation: 'en_attente' });
  await chauffeur('suspendu', { statutCompte: 'suspendu' });
  await chauffeur('banni', { statutCompte: 'banni' });
  await chauffeur('occupe');
  await chauffeur('sansAppareil', {}, false);
  await db.doc('users/awa').set({ role: 'client', statut: 'EN_LIGNE' });
  await jeton('awa', 'jetonClient');
  await courseActive('en_cours', { chauffeurId: 'occupe' });

  const n = await notifierNouvelleCourse(db, fcm, 'nouvelle');
  assert.equal(n, 2);
  assert.equal(fcm.envois.length, 1);
  assert.deepEqual([...fcm.envois[0].jetons].sort(), ['jeton_libre1', 'jeton_libre2']);
  const { push } = fcm.envois[0];
  assert.equal(push.titre, 'Nouvelle course');
  assert.equal(push.corps, 'Plateau → Almadies · 2 300 FCFA');
  assert.equal(push.canal, 'courses');
  assert.deepEqual(push.donnees, { type: 'course', courseId: 'nouvelle' });
  assert.equal(push.lien, LIENS.chauffeur);
  assert.equal(push.dureeVieSecondes, 120);
});

test('nouvelle course : colis, course déjà prise ou inconnue, plafond de chauffeurs', async () => {
  await db.doc('courses/colis').set({ clientId: 'awa', statut: 'en_attente', type: 'COLIS', adresseDepart: 'A', adresseArrivee: 'B', prixFcfa: 1500 });
  await chauffeur('libre');
  await notifierNouvelleCourse(db, fcm, 'colis');
  assert.equal(fcm.envois[0].push.titre, 'Nouveau colis à livrer');

  fcm.envois = [];
  await db.doc('courses/prise').set({ clientId: 'awa', statut: 'acceptee', type: 'PASSAGER', adresseDepart: 'A', adresseArrivee: 'B' });
  assert.equal(await notifierNouvelleCourse(db, fcm, 'prise'), 0);
  assert.equal(await notifierNouvelleCourse(db, fcm, 'inconnue'), 0);
  assert.equal(await notifierNouvelleCourse(db, undefined, 'colis'), 0);
  assert.equal(fcm.envois.length, 0);

  for (let i = 0; i < MAX_CHAUFFEURS_PREVENUS + 10; i++) await chauffeur(`c${i}`);
  await notifierNouvelleCourse(db, fcm, 'colis');
  assert.ok(fcm.envois[0].jetons.length <= MAX_CHAUFFEURS_PREVENUS);
});

// ---------------------------------------------------------------------
// Branchement sur le paiement, l'annulation et la surveillance
// ---------------------------------------------------------------------

function fournisseur() {
  return new FournisseurSimule('secret', 'https://page', []);
}

async function commande() {
  await db.doc('commandes/cmd1').set({
    clientId: 'awa', statut: 'en_attente_paiement', type: 'PASSAGER', adresseDepart: 'Plateau', adresseArrivee: 'Almadies',
    latitudeDepart: 14.69, longitudeDepart: -17.44, latitudeArrivee: 14.74, longitudeArrivee: -17.51,
    distanceKm: 10, sourceDistance: 'google', prixFcfa: 2300, methodePaiement: 'WAVE', fournisseur: 'simulation',
    sessionPaiementId: 'sim_abc',
  });
}

test('paiement confirmé : la course est créée puis les chauffeurs libres sont prévenus', async () => {
  await commande();
  await chauffeur('libre');
  const r = await traiterEvenement(db, fournisseur(), { sessionId: 'sim_abc', commandeId: 'cmd1', reussi: true, montantFcfa: 2300, devise: 'XOF' }, midi, fcm);
  assert.equal(r, 'course_creee');
  assert.equal(fcm.envois.length, 1);
  assert.deepEqual(fcm.envois[0].jetons, ['jeton_libre']);
  const courseId = (await db.doc('commandes/cmd1').get()).get('courseId');
  assert.equal(fcm.envois[0].push.donnees.courseId, courseId);
});

test('paiement confirmé alors que FCM est en panne : la course est créée quand même', async () => {
  await commande();
  await chauffeur('libre');
  fcm.enPanne = true;
  const r = await traiterEvenement(db, fournisseur(), { sessionId: 'sim_abc', commandeId: 'cmd1', reussi: true, montantFcfa: 2300, devise: 'XOF' }, midi, fcm);
  assert.equal(r, 'course_creee');
  assert.equal((await db.collection('courses').get()).size, 1);
});

test('paiement refusé : aucune notification ; confirmation rejouée : une seule notification', async () => {
  await commande();
  await chauffeur('libre');
  await traiterEvenement(db, fournisseur(), { sessionId: 'sim_abc', commandeId: 'cmd1', reussi: false, montantFcfa: 2300, devise: 'XOF' }, midi, fcm);
  assert.equal(fcm.envois.length, 0);

  await db.doc('commandes/cmd1').update({ statut: 'en_attente_paiement' });
  const ok = { sessionId: 'sim_abc', commandeId: 'cmd1', reussi: true, montantFcfa: 2300, devise: 'XOF' };
  assert.equal(await traiterEvenement(db, fournisseur(), ok, midi, fcm), 'course_creee');
  assert.equal(await traiterEvenement(db, fournisseur(), ok, midi, fcm), 'deja_traite');
  assert.equal(fcm.envois.length, 1);
});

test('le chauffeur annule : le client est prévenu ; le client qui annule lui-même ne l\'est pas', async () => {
  await courseActive();
  await annulerCourse(db, fournisseur(), 'moussa', { courseId: 'c1', motif: 'panne' }, midi, fcm);
  assert.equal(fcm.envois.length, 1);
  assert.deepEqual(fcm.envois[0].jetons, ['jetonAwa']);
  assert.equal(fcm.envois[0].push.titre, 'Course annulée par votre chauffeur');
  assert.equal(fcm.envois[0].push.donnees.type, 'annulee');
  assert.equal(fcm.envois[0].push.lien, LIENS.activiteClient);

  fcm.envois = [];
  await db.doc('courses/c2').set({ clientId: 'awa', chauffeurId: null, statut: 'en_attente', type: 'PASSAGER' });
  await annulerCourse(db, fournisseur(), 'awa', { courseId: 'c2' }, midi, fcm);
  assert.equal(fcm.envois.length, 0);
});

test('surveillance : course sans chauffeur au bout de 10 minutes, le client est prévenu', async () => {
  await db.doc('courses/vieille').set({
    clientId: 'awa', chauffeurId: null, statut: 'en_attente', type: 'PASSAGER',
    timestamp: Timestamp.fromDate(new Date(midi.getTime() - 11 * 60_000)),
  });
  const bilan = await surveiller(db, fournisseur(), midi, fcm);
  assert.equal(bilan.sansChauffeur, 1);
  assert.equal(fcm.envois.length, 1);
  assert.equal(fcm.envois[0].push.titre, 'Aucun chauffeur disponible');
  assert.deepEqual(fcm.envois[0].jetons, ['jetonAwa']);
});

test('liens des notifications du site : adresses en # (routeur du site), toutes valides', () => {
  for (const lien of Object.values(LIENS)) {
    assert.match(lien, /^\/#\/[a-z/-]+$/);
    // Absolu et en https : exigé par les navigateurs pour ouvrir le lien.
    assert.ok(new URL(`${SITE}${lien}`).protocol === 'https:');
  }
});
