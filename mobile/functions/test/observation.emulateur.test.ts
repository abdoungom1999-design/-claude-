// Observation (phase C de la sécurité) sur l'émulateur Firestore : opérations
// sensibles de l'Admin et paiements en attente. On regarde et on le dit, on ne
// refuse rien et on ne casse jamais l'opération observée.
// npm run test:emulateur (lance l'émulateur, puis ces tests).
import { after, afterEach, before, beforeEach, mock, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import type { EnvoiPush } from '../src/notifications';
import {
  COMMANDES_EN_ATTENTE_OBSERVEES,
  observerAjustement,
  observerCommandesEnAttente,
  observerOperationAdmin,
  observerRetraitTraite,
  PLAFONDS_ADMIN_JOUR,
} from '../src/observation';
import { ajusterPortefeuille } from '../src/admin';

const midi = new Date(Date.UTC(2026, 10, 13, 12));
const lendemain = new Date(Date.UTC(2026, 10, 14, 9));

let app: App;
let db: Firestore;
let pushs: EnvoiPush[];
let avertissements: Array<[string, Record<string, unknown> | undefined]>;
let erreurs: unknown[];

/** « Prévenir les Admin », sans Firebase Cloud Messaging : note les notifications. */
const prevenir = async (push: EnvoiPush) => {
  pushs.push(push);
  return 1;
};

const compteur = async (admin: string, jour = '2026-11-13') =>
  (await db.doc(`controle_admin/${admin}_${jour}`).get()).data() as
    | { adminId: string; jour: string; creditsFcfa: number; versementsFcfa: number; operations: number }
    | undefined;

const credit = (montantFcfa: number, extra: Record<string, unknown> = {}) => ({ clientId: 'awa', montantFcfa, motif: 'Geste commercial', ...extra });

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' }, 'observation');
  db = getFirestore(app);
});

after(() => deleteApp(app));

beforeEach(async () => {
  for (const nom of ['users', 'retraits', 'commandes', 'controle_admin', 'journal_admin']) await db.recursiveDelete(db.collection(nom));
  await db.recursiveDelete(db.doc('portefeuilles/awa'));
  await db.doc('users/admin').set({ role: 'admin', nom: 'Abdou' });
  await db.doc('users/admin2').set({ role: 'admin', email: 'admin2@sprint.sn' });
  await db.doc('users/awa').set({ role: 'client', nom: 'Awa Ndiaye' });
  await db.doc('users/fatou').set({ role: 'client' });
  pushs = [];
  avertissements = [];
  erreurs = [];
  mock.method(logger, 'info', () => {});
  mock.method(logger, 'warn', (texte: string, donnees?: Record<string, unknown>) => avertissements.push([texte, donnees]));
  mock.method(logger, 'error', (...args: unknown[]) => erreurs.push(args));
});
afterEach(() => mock.restoreAll());

test('crédit : compteur du jour, et notification à tous les Admin avec le nom du client, le montant, le motif', async () => {
  await observerAjustement(db, 'admin', credit(5000), midi, prevenir);
  assert.deepEqual(await compteur('admin'), {
    adminId: 'admin', jour: '2026-11-13', creditsFcfa: 5000, versementsFcfa: 0, operations: 1, majLe: Timestamp.fromDate(midi),
  });
  assert.equal(pushs.length, 1);
  assert.equal(pushs[0].titre, 'Admin : crédit de portefeuille');
  assert.match(pushs[0].corps, /5 000 FCFA ajoutés au portefeuille de Awa Ndiaye, par Abdou\. Motif : Geste commercial\./);
  assert.match(pushs[0].corps, /Ce n'est pas vous \?/);
  assert.deepEqual(pushs[0].donnees, { type: 'controle_admin', operation: 'credit' });
  assert.equal(pushs[0].lien, '/#/admin');
  assert.equal(avertissements.length, 0, 'un crédit ordinaire n\'est pas un avertissement');
});

test('débit : compté, aucune notification', async () => {
  await observerAjustement(db, 'admin', credit(-3000), midi, prevenir);
  const c = await compteur('admin');
  assert.equal(c?.operations, 1);
  assert.equal(c?.creditsFcfa, 0, 'un débit n\'est pas un crédit');
  assert.equal(pushs.length, 0);
});

test('plafond de crédits franchi : une alerte nette, aucun refus, puis plus d\'alerte de plafond le même jour', async () => {
  await observerAjustement(db, 'admin', credit(100_000), midi, prevenir);
  assert.equal(pushs[0].titre, 'Admin : crédit de portefeuille');
  await observerAjustement(db, 'admin', credit(60_000), midi, prevenir);
  assert.equal(pushs.length, 2);
  assert.equal(pushs[1].titre, 'Admin : plafond du jour dépassé');
  assert.match(pushs[1].corps, /Attention : plafond de crédits du jour \(150 000 FCFA\) dépassé : 160 000 FCFA\./);
  assert.equal(avertissements.length, 1);
  assert.match(avertissements[0][0], /plafond journalier dépassé \(observation : rien n'est refusé\)/);
  await observerAjustement(db, 'admin', credit(10_000), midi, prevenir);
  assert.equal(pushs.length, 3);
  assert.doesNotMatch(pushs[2].corps, /Attention/);
  assert.equal(avertissements.length, 1, 'le plafond n\'est franchi qu\'une fois');
  assert.equal((await compteur('admin'))?.creditsFcfa, 170_000, 'tout est compté, rien n\'est refusé');
});

test('plafond d\'opérations : alerte à la seizième, même pour des débits', async () => {
  for (let i = 0; i < PLAFONDS_ADMIN_JOUR.operations; i++) await observerAjustement(db, 'admin', credit(-1000), midi, prevenir);
  assert.equal(pushs.length, 0);
  await observerAjustement(db, 'admin', credit(-1000), midi, prevenir);
  assert.equal(pushs.length, 1);
  assert.match(pushs[0].corps, /plus de 15 opérations sensibles dans la journée \(16\)/);
});

test('retrait versé : montant, client et moyen relus dans le retrait enregistré ; refusé : compté sans notification', async () => {
  await db.doc('retraits/rtr_a').set({ clientId: 'awa', montantFcfa: 20_000, moyen: 'ORANGE_MONEY', statut: 'verse' });
  await db.doc('retraits/rtr_b').set({ clientId: 'awa', montantFcfa: 7000, moyen: 'WAVE', statut: 'refuse' });
  await observerRetraitTraite(db, 'admin', { retraitId: 'rtr_a' }, 'verse', midi, prevenir);
  assert.equal(pushs.length, 1);
  assert.equal(pushs[0].titre, 'Admin : retrait versé');
  assert.match(pushs[0].corps, /20 000 FCFA versés à Awa Ndiaye \(Orange Money\), par Abdou\./);
  await observerRetraitTraite(db, 'admin', { retraitId: 'rtr_b' }, 'refuse', midi, prevenir);
  assert.equal(pushs.length, 1, 'un refus rend l\'argent au client : rien à signaler');
  const c = await compteur('admin');
  assert.equal(c?.versementsFcfa, 20_000);
  assert.equal(c?.operations, 2);
});

test('plafond de retraits versés franchi : alerte', async () => {
  await db.doc('retraits/rtr_a').set({ clientId: 'awa', montantFcfa: 50_000, moyen: 'WAVE', statut: 'verse' });
  for (let i = 0; i < 6; i++) await observerRetraitTraite(db, 'admin', { retraitId: 'rtr_a' }, 'verse', midi, prevenir);
  assert.equal(pushs.filter((p) => p.titre === 'Admin : plafond du jour dépassé').length, 0, '300 000 FCFA : pile au plafond, pas au-delà');
  await observerRetraitTraite(db, 'admin', { retraitId: 'rtr_a' }, 'verse', midi, prevenir);
  const alerte = pushs.filter((p) => p.titre === 'Admin : plafond du jour dépassé');
  assert.equal(alerte.length, 1);
  assert.match(alerte[0].corps, /plafond de retraits versés du jour \(300 000 FCFA\) dépassé : 350 000 FCFA/);
});

test('un compteur par Admin et par jour', async () => {
  await observerAjustement(db, 'admin', credit(1000), midi, prevenir);
  await observerAjustement(db, 'admin2', credit(2000), midi, prevenir);
  await observerAjustement(db, 'admin', credit(4000), lendemain, prevenir);
  assert.equal((await compteur('admin'))?.creditsFcfa, 1000);
  assert.equal((await compteur('admin2'))?.creditsFcfa, 2000);
  assert.equal((await compteur('admin', '2026-11-14'))?.creditsFcfa, 4000);
  assert.match(pushs[1].corps, /par admin2@sprint\.sn/, 'à défaut de nom, l\'e-mail');
});

test('compte sans nom ni e-mail : reconnu par le début de son identifiant', async () => {
  await observerOperationAdmin(db, 'admin', { type: 'credit', montantFcfa: 1000, clientId: 'fatou' }, midi, prevenir);
  assert.match(pushs[0].corps, /portefeuille de le compte fatou…, par Abdou\./);
});

test('rien n\'est cassé : notification en panne, base en panne, données invalides', async () => {
  await observerAjustement(db, 'admin', credit(5000), midi, async () => {
    throw new Error('FCM en panne');
  });
  assert.equal((await compteur('admin'))?.creditsFcfa, 5000, 'le compteur est écrit malgré la panne de notification');
  assert.equal(erreurs.length, 1);

  const basePannee = { collection: () => { throw new Error('Firestore en panne'); } } as unknown as Firestore;
  await assert.doesNotReject(observerAjustement(basePannee, 'admin', credit(5000), midi, prevenir));
  await assert.doesNotReject(observerRetraitTraite(basePannee, 'admin', { retraitId: 'rtr_a' }, 'verse', midi, prevenir));
  await assert.doesNotReject(observerCommandesEnAttente(basePannee, 'awa'));

  const avant = (await db.collection('controle_admin').get()).size;
  for (const donnees of [undefined, null, 'x', {}, { clientId: 1, montantFcfa: 'a' }, { clientId: 'awa', montantFcfa: 0 }]) {
    await observerAjustement(db, 'admin', donnees, midi, prevenir);
  }
  await observerAjustement(db, undefined, credit(5000), midi, prevenir);
  await observerRetraitTraite(db, 'admin', { retraitId: 'rtr_inconnu' }, 'verse', midi, prevenir);
  await observerRetraitTraite(db, 'admin', null, 'verse', midi, prevenir);
  assert.equal((await db.collection('controle_admin').get()).size, avant, 'données invalides : rien d\'écrit');
});

test('l\'observation suit une vraie opération sans la changer : ajustement réussi observé, ajustement refusé non observé', async () => {
  const resultat = await ajusterPortefeuille(db, 'admin', credit(5000), midi);
  assert.equal(resultat.soldeFcfa, 5000);
  await observerAjustement(db, 'admin', credit(5000), midi, prevenir);
  assert.equal((await compteur('admin'))?.operations, 1);
  assert.equal((await db.doc('portefeuilles/awa').get()).get('soldeFcfa'), 5000, 'l\'observation ne touche pas au solde');
  const journal = await db.collection('journal_admin').get();
  assert.equal(journal.size, 1, 'l\'observation n\'écrit pas dans le journal des actions');
});

test('commandes en attente : comptées par client, signalées à partir de 5, rien de refusé', async () => {
  for (let i = 0; i < COMMANDES_EN_ATTENTE_OBSERVEES - 1; i++) {
    await db.doc(`commandes/a${i}`).set({ clientId: 'awa', statut: 'en_attente_paiement' });
  }
  await db.doc('commandes/payee').set({ clientId: 'awa', statut: 'payee' });
  await db.doc('commandes/autre').set({ clientId: 'fatou', statut: 'en_attente_paiement' });
  assert.equal(await observerCommandesEnAttente(db, 'awa'), COMMANDES_EN_ATTENTE_OBSERVEES - 1);
  assert.equal(avertissements.length, 0);
  await db.doc('commandes/a5').set({ clientId: 'awa', statut: 'en_attente_paiement' });
  assert.equal(await observerCommandesEnAttente(db, 'awa'), COMMANDES_EN_ATTENTE_OBSERVEES);
  assert.equal(avertissements.length, 1);
  assert.match(avertissements[0][0], /paiements en attente nombreux chez un même client \(rien n'est refusé\)/);
  assert.equal(await observerCommandesEnAttente(db, 'fatou'), 1);
  assert.equal(await observerCommandesEnAttente(db, undefined), 0);
});
