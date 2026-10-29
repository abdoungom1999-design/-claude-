// Orange Money branché sur le parcours de paiement, sur l'émulateur Firestore
// et avec un faux Orange (aucun réseau) : npm run test:emulateur.
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { rembourserCourseAdmin } from '../src/admin';
import { calculDistance } from '../src/distances';
import { ErreurFournisseur, FournisseurSimule, type FournisseurDuMoyen } from '../src/fournisseurs';
import type { ClientGoogle } from '../src/google';
import type { Methode } from '../src/methodes_paiement';
import { ClientOrangeMoney, URL_ORANGE_MONEY } from '../src/orange_money';
import {
  appliquerTransactionOrange,
  FENETRE_RELECTURE_MS,
  FournisseurOrangeMoney,
  fournisseursDuMoyen,
  rattraperOrange,
  repondreNotificationOrange,
  type ConfigOrange,
} from '../src/paiement_orange';
import { annulerCourse, creerPaiement as creerPaiementCore, surveiller } from '../src/paiements';
import { creerRecharge as creerRechargeCore, surveillerRecharges } from '../src/portefeuille';
import { CODE_MARCHAND_TEST, FauxOrange } from './faux_orange';

const PLATEAU = { latitude: 14.6928, longitude: -17.4467 };
const ALMADIES = { latitude: 14.7456, longitude: -17.5134 };
const midi = new Date(Date.UTC(2026, 9, 29, 12));
const minutes = (n: number) => new Date(midi.getTime() + n * 60 * 1000);
/** Course de 2 300 FCFA (Plateau -> Almadies, 10,2 km, midi). */
const PRIX = 2300;
const CLE = 'cle-de-notification-de-test-assez-longue-0123456789';

/** Orange Money ouvert, comme il le sera après le go du client. */
const OUVERTES: Methode[] = ['WAVE', 'ORANGE_MONEY', 'PORTEFEUILLE'];
const RECHARGE_OUVERTES: Methode[] = ['WAVE', 'ORANGE_MONEY'];

const demande = (extra: Record<string, unknown> = {}) => ({
  type: 'PASSAGER',
  depart: PLATEAU,
  arrivee: ALMADIES,
  adresseDepart: 'Plateau',
  adresseArrivee: 'Almadies',
  methodePaiement: 'ORANGE_MONEY',
  prixAttendu: PRIX,
  ...extra,
});

let app: App;
let db: Firestore;
let orange: FauxOrange;
let config: ConfigOrange;
let simule: FournisseurSimule;
let remboursementsWave: string[];
/** Fournisseurs à l'heure de la demande (la fenêtre de relecture part de là). */
let fournisseurs: (quand: Date) => FournisseurDuMoyen;

const googleFactice = { itineraire: async () => ({ distanceKm: 10.2 }) } as unknown as ClientGoogle;

const creerPaiement = (donnees: unknown = demande(), quand = midi, methodes: Methode[] = OUVERTES) =>
  creerPaiementCore(db, calculDistance(db, googleFactice, () => quand), fournisseurs(quand), 'awa', donnees, quand, undefined, methodes);

const creerRecharge = (montantFcfa: number, quand = midi) =>
  creerRechargeCore(db, fournisseurs(quand), 'awa', { montantFcfa, methodePaiement: 'ORANGE_MONEY' }, quand, RECHARGE_OUVERTES);

/** Notification d'Orange (POST, avec la clé enregistrée sauf mention contraire ; `null` : sans en-tête). */
const notifier = (corpsBrut: Buffer, quand = midi, autorisation: string | null = `Basic ${CLE}`) =>
  repondreNotificationOrange(
    db,
    config,
    CLE,
    { methode: 'POST', autorisation: autorisation ?? undefined, corpsBrut },
    async () => simule,
    quand,
  );

const commande = async (id: string) => (await db.doc(`commandes/${id}`).get()).data()!;
const nombre = async (collection: string) => (await db.collection(collection).get()).size;
const solde = async (uid: string) => ((await db.doc(`portefeuilles/${uid}`).get()).get('soldeFcfa') as number | undefined) ?? 0;

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

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' });
  db = getFirestore(app);
});

after(() => deleteApp(app));

beforeEach(async () => {
  orange = new FauxOrange();
  config = { client: orange.client(), codeMarchand: CODE_MARCHAND_TEST };
  remboursementsWave = [];
  simule = new FournisseurSimule('secret', 'https://page', remboursementsWave);
  fournisseurs = (quand) => fournisseursDuMoyen(simule, () => new FournisseurOrangeMoney(config, () => quand));
  for (const nom of ['users', 'courses', 'commandes', 'recharges', 'portefeuilles', 'distances', 'config', 'tickets', 'journal_admin']) {
    await db.recursiveDelete(db.collection(nom));
  }
  await db.doc('users/chef').set({ role: 'admin' });
  await db.doc('users/awa').set({ role: 'client', nom: 'Awa' });
  await db.doc('users/moussa').set({ role: 'conducteur', statutValidation: 'valide' });
});

// --- Demande de paiement -------------------------------------------------

test('demande Orange Money : QR chez Orange, commande en attente avec le lien Max It, relecture 1 heure, aucune course', async () => {
  const r = await creerPaiement();
  assert.equal(r.prixFcfa, PRIX);
  assert.equal(r.lienPaiement, 'https://sugu.orange-sonatel.com/mp/maxit1');
  assert.deepEqual(orange.qrCodes, [
    { reference: r.commandeId, montantFcfa: PRIX, code: CODE_MARCHAND_TEST, name: 'Sprint', validity: 1080, isSingleUse: true },
  ]);
  const c = await commande(r.commandeId);
  assert.equal(c.statut, 'en_attente_paiement');
  assert.equal(c.methodePaiement, 'ORANGE_MONEY');
  assert.equal(c.fournisseur, 'orange_money');
  assert.equal(c.sessionPaiementId, `om_${r.commandeId}`);
  assert.equal(c.lienPaiement, r.lienPaiement);
  assert.equal((c.expireLe as Timestamp).toMillis(), minutes(20).getTime());
  assert.equal((c.relectureFinLe as Timestamp).toMillis(), midi.getTime() + FENETRE_RELECTURE_MS);
  assert.equal(await nombre('courses'), 0);
});

test('Orange Money fermé (réglage actuel) : refusé avant d\'appeler Orange', async () => {
  const erreur = await refuse(creerPaiement(demande(), midi, ['WAVE', 'PORTEFEUILLE']), 'failed-precondition');
  assert.match(erreur.message, /Orange Money n'est pas encore disponible/);
  await refuse(
    creerRechargeCore(db, fournisseurs(midi), 'awa', { montantFcfa: 5000, methodePaiement: 'ORANGE_MONEY' }, midi),
    'failed-precondition',
  );
  assert.deepEqual(orange.requetes, []);
  assert.equal(await nombre('commandes'), 0);
  assert.equal(await nombre('recharges'), 0);
});

test('chaque moyen reste chez son fournisseur : Wave par Wave, Orange Money par Orange', async () => {
  const wave = await creerPaiement(demande({ methodePaiement: 'WAVE' }));
  assert.equal((await commande(wave.commandeId)).fournisseur, 'simulation');
  assert.match(wave.lienPaiement!, /^https:\/\/page\?session=sim_/);
  assert.equal((await commande(wave.commandeId)).relectureFinLe, undefined);
  assert.deepEqual(orange.qrCodes, []);
  const om = await creerPaiement();
  assert.equal((await commande(om.commandeId)).fournisseur, 'orange_money');
  assert.equal(orange.qrCodes.length, 1);
});

test('Orange non configuré ou injoignable : paiement Orange indisponible, rien créé ; Wave continue', async () => {
  fournisseurs = () =>
    fournisseursDuMoyen(simule, () => {
      throw new ErreurFournisseur('Orange Money n\'est pas configuré.');
    });
  await refuse(creerPaiement(), 'unavailable');
  await refuse(creerRecharge(5000), 'unavailable');

  const injoignable = new ClientOrangeMoney({
    urlBase: URL_ORANGE_MONEY.bacASable,
    idClient: 'id-de-test',
    secretClient: 'secret-de-test',
    fetcher: (async () => {
      throw new TypeError('fetch failed');
    }) as typeof fetch,
  });
  fournisseurs = (quand) =>
    fournisseursDuMoyen(simule, () => new FournisseurOrangeMoney({ client: injoignable, codeMarchand: CODE_MARCHAND_TEST }, () => quand));
  await refuse(creerPaiement(), 'unavailable');
  await refuse(creerRecharge(5000), 'unavailable');
  assert.equal(await nombre('commandes'), 0);
  assert.equal(await nombre('recharges'), 0);

  const wave = await creerPaiement(demande({ methodePaiement: 'WAVE' }));
  assert.equal((await commande(wave.commandeId)).statut, 'en_attente_paiement');
});

// --- Notification d'Orange ---------------------------------------------

test('paiement réussi : notification vérifiée et relue chez Orange, course créée ; rejouée : déjà traitée', async () => {
  const { commandeId } = await creerPaiement();
  const id = orange.payer(commandeId, PRIX);

  const r = await notifier(orange.notification(id), minutes(3));
  assert.deepEqual(r, { statut: 202, corps: '', resultat: 'course_creee' });
  assert.ok(orange.requetes.includes('GET /api/eWallet/v1/transactions'), 'relue chez Orange');
  const c = await commande(commandeId);
  assert.equal(c.statut, 'payee');
  const course = (await db.doc(`courses/${c.courseId}`).get()).data()!;
  assert.equal(course.statut, 'en_attente');
  assert.equal(course.prixFcfa, PRIX);
  assert.equal(course.methodePaiement, 'ORANGE_MONEY');
  assert.equal(course.modePaiement, 'orange_money');

  // Orange livre « au moins une fois » : la même notification ne crée jamais une deuxième course.
  assert.equal((await notifier(orange.notification(id), minutes(4))).resultat, 'deja_traite');
  assert.equal(await nombre('courses'), 1);
});

test('notification sans la bonne clé : 401, Orange n\'est pas interrogé, rien créé', async () => {
  const { commandeId } = await creerPaiement();
  const id = orange.payer(commandeId, PRIX);
  const avant = orange.requetes.length;
  for (const autorisation of [null, '', 'Basic mauvaise-cle', `Bearer ${CLE}`]) {
    assert.equal((await notifier(orange.notification(id), midi, autorisation)).statut, 401);
  }
  assert.equal(orange.requetes.length, avant);
  assert.equal((await commande(commandeId)).statut, 'en_attente_paiement');
  assert.equal(await nombre('courses'), 0);
});

test('seul ce qu\'Orange dit compte : statut, montant et référence de la notification ne font pas foi', async () => {
  const { commandeId } = await creerPaiement();
  // La notification annonce un succès, Orange dit « refusé » : commande échouée, pas de course.
  const refusee = orange.payer(commandeId, PRIX, { statut: 'FAILED' });
  assert.equal((await notifier(orange.notification(refusee, { status: 'SUCCESS' }))).resultat, 'echec_enregistre');
  assert.equal((await commande(commandeId)).statut, 'echouee');
  assert.equal(await nombre('courses'), 0);

  // Montant annoncé faux, mais Orange a bien encaissé le prix : c'est Orange qui compte.
  const b = await creerPaiement();
  const paye = orange.payer(b.commandeId, PRIX);
  assert.equal((await notifier(orange.notification(paye, { amount: { value: 1, unit: 'XOF' } }))).resultat, 'course_creee');

  // Référence annoncée différente de celle d'Orange : rien n'est fait.
  const c = await creerPaiement();
  const autre = orange.payer(c.commandeId, PRIX);
  assert.equal((await notifier(orange.notification(autre, { reference: b.commandeId }))).resultat, 'non_confirmee');
  assert.equal((await commande(c.commandeId)).statut, 'en_attente_paiement');

  // Transaction inconnue d'Orange : rien n'est fait (202, Orange n'insiste pas).
  const inventee = Buffer.from(
    JSON.stringify({
      transactionId: 'MP999999.9999.Z99999',
      reference: c.commandeId,
      status: 'SUCCESS',
      amount: { value: PRIX, unit: 'XOF' },
      type: 'MERCHANT_PAYMENT',
    }),
  );
  assert.deepEqual(await notifier(inventee), { statut: 202, corps: '', resultat: 'non_confirmee' });
  assert.equal(await nombre('courses'), 1);
});

test('paiement à un autre marchand avec notre référence, ou d\'un autre type : jamais appliqué', async () => {
  const { commandeId } = await creerPaiement();
  const ailleurs = orange.payer(commandeId, PRIX, { code: '654321' });
  assert.equal((await notifier(orange.notification(ailleurs))).resultat, 'non_confirmee');
  const depot = orange.payer(commandeId, PRIX, { type: 'CASHIN' });
  assert.equal((await notifier(orange.notification(depot))).resultat, 'non_confirmee');
  assert.equal((await rattraperOrange(db, config, simule, minutes(5))).appliquees, 0);
  assert.equal((await commande(commandeId)).statut, 'en_attente_paiement');
  assert.equal(await nombre('courses'), 0);
});

test('montant ou devise différents chez Orange : anomalie (visible de l\'Admin), pas de course', async () => {
  const a = await creerPaiement();
  assert.equal((await notifier(orange.notification(orange.payer(a.commandeId, 100)))).resultat, 'anomalie');
  const b = await creerPaiement();
  assert.equal((await notifier(orange.notification(orange.payer(b.commandeId, PRIX, { devise: 'EUR' })))).resultat, 'anomalie');
  assert.equal((await commande(a.commandeId)).statut, 'anomalie');
  assert.equal(await nombre('courses'), 0);
});

test('transaction encore en cours chez Orange : rien appliqué, la commande attend', async () => {
  const { commandeId } = await creerPaiement();
  const id = orange.payer(commandeId, PRIX, { statut: 'PENDING' });
  assert.equal((await notifier(orange.notification(id, { status: 'SUCCESS' }))).resultat, 'en_attente');
  assert.equal((await commande(commandeId)).statut, 'en_attente_paiement');
});

// --- Remboursements : sur le solde Sprint (décision du client) ----------

test('refusé puis payé (nouvel essai sur le même QR) : l\'argent est rendu sur le solde Sprint', async () => {
  const { commandeId } = await creerPaiement();
  assert.equal((await notifier(orange.notification(orange.payer(commandeId, PRIX, { statut: 'FAILED' })))).resultat, 'echec_enregistre');
  assert.equal((await notifier(orange.notification(orange.payer(commandeId, PRIX)), minutes(2))).resultat, 'rembourse');
  const c = await commande(commandeId);
  assert.equal(c.statut, 'remboursee');
  assert.equal(c.rembourseSurSolde, true);
  assert.equal(await solde('awa'), PRIX);
  assert.deepEqual(remboursementsWave, [], 'jamais un remboursement Wave pour un paiement Orange');
  assert.equal(await nombre('courses'), 0);
});

test('payé après l\'expiration de la commande : remboursé sur le solde Sprint, une seule fois', async () => {
  const { commandeId } = await creerPaiement();
  assert.equal((await surveiller(db, simule, minutes(21))).expirees, 1);
  const id = orange.payer(commandeId, PRIX);
  assert.equal((await notifier(orange.notification(id), minutes(22))).resultat, 'rembourse');
  assert.equal((await notifier(orange.notification(id), minutes(23))).resultat, 'deja_traite');
  assert.equal(await solde('awa'), PRIX);
  const mouvement = (await db.doc(`portefeuilles/awa/mouvements/remboursement_${commandeId}`).get()).data()!;
  assert.equal(mouvement.type, 'remboursement');
  assert.equal(mouvement.montantFcfa, PRIX);
  assert.equal(mouvement.note, 'paiement_tardif');
});

test('course payée par Orange puis annulée : remboursée sur le solde Sprint, jamais chez Wave', async () => {
  const { commandeId } = await creerPaiement();
  await notifier(orange.notification(orange.payer(commandeId, PRIX)));
  const courseId = (await commande(commandeId)).courseId as string;
  assert.deepEqual(await annulerCourse(db, simule, 'awa', { courseId }, minutes(2)), { rembourse: true });
  const c = await commande(commandeId);
  assert.equal(c.statut, 'remboursee');
  assert.equal(c.motifRemboursement, 'course_annulee');
  assert.equal(c.rembourseSurSolde, true);
  assert.equal(await solde('awa'), PRIX);
  assert.deepEqual(remboursementsWave, []);
});

test('remboursement par l\'Admin d\'une course payée par Orange : sur le solde Sprint, et le ticket le dit', async () => {
  const { commandeId } = await creerPaiement();
  await notifier(orange.notification(orange.payer(commandeId, PRIX)));
  const courseId = (await commande(commandeId)).courseId as string;
  await db.doc(`courses/${courseId}`).update({ statut: 'terminee', chauffeurId: 'moussa', commissionFcfa: 230 });
  await db.doc(`tickets/${courseId}`).set({ clientId: 'awa', statut: 'ouvert' });

  const r = await rembourserCourseAdmin(db, simule, 'chef', { courseId, motif: 'Course non effectuée' }, minutes(40));
  assert.equal(r.rembourse, true);
  assert.equal(await solde('awa'), PRIX);
  assert.deepEqual(remboursementsWave, []);
  const [message] = (await db.collection(`tickets/${courseId}/messages`).get()).docs.map((d) => d.get('texte') as string);
  assert.equal(message, `Votre course a été remboursée intégralement (${PRIX} FCFA) sur votre portefeuille Sprint.`);
});

// --- Recharge du portefeuille --------------------------------------------

test('recharge par Orange Money : QR « rch_… », solde crédité une seule fois', async () => {
  const { rechargeId, lienPaiement } = await creerRecharge(5000);
  assert.match(rechargeId, /^rch_[0-9a-f]{24}$/);
  assert.equal(lienPaiement, 'https://sugu.orange-sonatel.com/mp/maxit1');
  const r = (await db.doc(`recharges/${rechargeId}`).get()).data()!;
  assert.equal(r.fournisseur, 'orange_money');
  assert.equal(r.sessionPaiementId, `om_${rechargeId}`);
  assert.equal((r.relectureFinLe as Timestamp).toMillis(), midi.getTime() + FENETRE_RELECTURE_MS);
  assert.equal(orange.qrCodes[0].reference, rechargeId);
  assert.equal(orange.qrCodes[0].montantFcfa, 5000);

  const id = orange.payer(rechargeId, 5000);
  assert.equal((await notifier(orange.notification(id))).resultat, 'recharge_creditee');
  assert.equal((await notifier(orange.notification(id))).resultat, 'deja_traite');
  assert.equal(await solde('awa'), 5000);
});

// --- Rattrapage par la surveillance --------------------------------------

test('notification perdue : la surveillance relit chez Orange et crée la course, une seule fois', async () => {
  const payee = await creerPaiement();
  const enCours = await creerPaiement();
  orange.payer(payee.commandeId, PRIX); // aucune notification

  const bilan = await rattraperOrange(db, config, simule, minutes(5));
  assert.deepEqual(bilan, { verifiees: 2, appliquees: 1, erreurs: 0, reportees: 0 });
  assert.equal((await commande(payee.commandeId)).statut, 'payee');
  assert.equal((await commande(enCours.commandeId)).statut, 'en_attente_paiement');
  // Passage suivant : la commande payée n'est plus relue, aucune deuxième course.
  assert.deepEqual(await rattraperOrange(db, config, simule, minutes(10)), { verifiees: 1, appliquees: 0, erreurs: 0, reportees: 0 });
  assert.equal(await nombre('courses'), 1);
});

test('rattrapage : payé après l\'expiration ou après un refus, notification perdue = remboursé ou crédité', async () => {
  const expiree = await creerPaiement();
  const refusee = await creerPaiement();
  const recharge = await creerRecharge(5000);
  await notifier(orange.notification(orange.payer(refusee.commandeId, PRIX, { statut: 'FAILED' })));
  await surveiller(db, simule, minutes(21));
  await surveillerRecharges(db, minutes(21));
  orange.payer(expiree.commandeId, PRIX);
  orange.payer(refusee.commandeId, PRIX);
  orange.payer(recharge.rechargeId, 5000);

  const bilan = await rattraperOrange(db, config, simule, minutes(30));
  assert.deepEqual(bilan, { verifiees: 3, appliquees: 3, erreurs: 0, reportees: 0 });
  assert.equal((await commande(expiree.commandeId)).statut, 'remboursee');
  assert.equal((await commande(refusee.commandeId)).statut, 'remboursee');
  assert.equal((await db.doc(`recharges/${recharge.rechargeId}`).get()).get('statut'), 'reussie');
  assert.equal(await solde('awa'), 2 * PRIX + 5000);
  assert.equal(await nombre('courses'), 0);
});

test('rattrapage : plus rien n\'est relu une heure après la demande', async () => {
  const { commandeId } = await creerPaiement();
  await surveiller(db, simule, minutes(21));
  orange.payer(commandeId, PRIX);
  assert.equal((await rattraperOrange(db, config, simule, minutes(61))).verifiees, 0);
  assert.equal((await commande(commandeId)).statut, 'expiree');
  // La notification, elle, reste traitée à tout moment.
  assert.equal((await notifier(orange.notification(orange.transactions[0].transactionId), minutes(90))).resultat, 'rembourse');
});

test('rattrapage : les demandes en attente d\'abord, au plus [max] recherches, arrêt si Orange demande de ralentir', async () => {
  const ancienne = await creerPaiement(demande(), minutes(0));
  await surveiller(db, simule, minutes(21)); // l'ancienne expire
  const recente = await creerPaiement(demande(), minutes(25));
  orange.payer(recente.commandeId, PRIX);
  orange.payer(ancienne.commandeId, PRIX);
  // Une seule recherche : la demande encore en attente passe avant l'expirée, plus ancienne.
  assert.deepEqual(await rattraperOrange(db, config, simule, minutes(26), undefined, 1), {
    verifiees: 1,
    appliquees: 1,
    erreurs: 0,
    reportees: 1,
  });
  assert.equal((await commande(recente.commandeId)).statut, 'payee');
  assert.equal((await commande(ancienne.commandeId)).statut, 'expiree');

  orange.panneRecherche = 429;
  await creerPaiement(demande(), minutes(27));
  assert.deepEqual(await rattraperOrange(db, config, simule, minutes(28)), { verifiees: 1, appliquees: 0, erreurs: 1, reportees: 1 });
  orange.panneRecherche = 503;
  assert.deepEqual(await rattraperOrange(db, config, simule, minutes(29)), { verifiees: 2, appliquees: 0, erreurs: 2, reportees: 0 });
  orange.panneRecherche = undefined;
  assert.deepEqual(await rattraperOrange(db, config, simule, minutes(30)), { verifiees: 2, appliquees: 1, erreurs: 0, reportees: 0 });
  assert.equal((await commande(ancienne.commandeId)).statut, 'remboursee');
});

test('transaction appliquée directement : sans référence, rien', async () => {
  const id = orange.payer(undefined, PRIX);
  const [t] = await config.client.rechercherTransactions({ transactionId: id });
  assert.equal(await appliquerTransactionOrange(db, t, CODE_MARCHAND_TEST, simule, midi), 'non_confirmee');
});
