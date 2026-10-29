// Orange Money branché sur le paiement : ce qui se teste sans base de données
// (les parcours complets sont dans paiement_orange.emulateur.test.ts).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { Firestore } from 'firebase-admin/firestore';
import { ErreurFournisseur, type CreateurSession, type FournisseurPaiement } from '../src/fournisseurs';
import { ClientOrangeMoney, URL_ORANGE_MONEY } from '../src/orange_money';
import {
  configurerOrange,
  FENETRE_RELECTURE_MS,
  FournisseurOrangeMoney,
  fournisseursDuMoyen,
  repondreNotificationOrange,
  VALIDITE_ORANGE_SECONDES,
} from '../src/paiement_orange';
import { DUREE_PAIEMENT_MS } from '../src/paiements';
import { CODE_MARCHAND_TEST, FauxOrange } from './faux_orange';

const CLE = 'cle-de-notification-de-test-assez-longue-0123456789';
const midi = new Date(Date.UTC(2026, 9, 29, 12));
/** Aucune de ces réponses ne touche à la base. */
const sansBase = {} as Firestore;
const sansRemboursement = async () => ({}) as FournisseurPaiement;

const wave: CreateurSession = { nom: 'simulation', creerSession: async () => ({ sessionId: 'sim_1', lienPaiement: 'https://page' }) };

test('chaque moyen a son fournisseur : Orange Money par Orange (jamais par le faux opérateur), Wave par Wave', () => {
  let appelsOrange = 0;
  const orange: CreateurSession = { nom: 'orange_money', creerSession: async () => ({ sessionId: 'om_1', lienPaiement: 'https://om' }) };
  const choix = fournisseursDuMoyen(wave, () => {
    appelsOrange++;
    return orange;
  });
  assert.equal(choix('WAVE'), wave);
  assert.equal(appelsOrange, 0, 'Orange n\'est préparé que pour un paiement Orange');
  assert.equal(choix('ORANGE_MONEY'), orange);
  assert.throws(() => choix('PORTEFEUILLE'), ErreurFournisseur, 'le solde Sprint n\'a pas de fournisseur');
});

test('configuration : complète ou rien (Orange Money alors indisponible), espaces de copier-coller retirés', () => {
  const complete = configurerOrange({ idClient: ' id ', secretClient: 'secret\n', codeMarchand: ` ${CODE_MARCHAND_TEST} ` });
  assert.ok(complete);
  assert.equal(complete.codeMarchand, CODE_MARCHAND_TEST);
  assert.ok(complete.client instanceof ClientOrangeMoney);
  assert.equal(complete.client.estBacASable, true, 'bac à sable par défaut');
  assert.equal(configurerOrange({ idClient: '', secretClient: 's', codeMarchand: CODE_MARCHAND_TEST }), null);
  assert.equal(configurerOrange({ idClient: 'i', secretClient: ' ', codeMarchand: CODE_MARCHAND_TEST }), null);
  for (const code of ['', '12345', '1234567', 'abcdef']) {
    assert.equal(configurerOrange({ idClient: 'i', secretClient: 's', codeMarchand: code }), null, code);
  }
});

test('demande de paiement : QR à usage unique au nom de Sprint, valable 18 minutes, lien Max It, relecture 1 heure', async () => {
  assert.equal(VALIDITE_ORANGE_SECONDES, 18 * 60);
  assert.ok(VALIDITE_ORANGE_SECONDES * 1000 < DUREE_PAIEMENT_MS, 'Orange confirme avant l\'expiration de la commande');
  const orange = new FauxOrange();
  const fournisseur = new FournisseurOrangeMoney({ client: orange.client(), codeMarchand: CODE_MARCHAND_TEST }, () => midi);
  assert.equal(fournisseur.nom, 'orange_money');

  const session = await fournisseur.creerSession('a1b2c3', 2300);
  assert.deepEqual(orange.qrCodes, [
    { reference: 'a1b2c3', montantFcfa: 2300, code: CODE_MARCHAND_TEST, name: 'Sprint', validity: 1080, isSingleUse: true },
  ]);
  assert.equal(session.sessionId, 'om_a1b2c3');
  assert.equal(session.lienPaiement, 'https://sugu.orange-sonatel.com/mp/maxit1');
  assert.equal(session.relectureFinLe?.getTime(), midi.getTime() + FENETRE_RELECTURE_MS);
  assert.equal(FENETRE_RELECTURE_MS, 60 * 60 * 1000);
});

test('demande de paiement : sans lien Max It, lien Orange Money puis lien court ; sans aucun lien, erreur', async () => {
  const reponses = [
    { deepLinks: { OM: 'https://sugu.orange-sonatel.com/om' }, shortLink: 'https://sugu.orange-sonatel.com/court' },
    { shortLink: 'https://sugu.orange-sonatel.com/court' },
    { qrCode: 'iVBORw0KGgo=' },
  ];
  const fetcher = (async (adresse: string | URL | Request) => {
    const corps = String(adresse).endsWith('/oauth/v1/token')
      ? { access_token: 'jeton', expires_in: 3600 }
      : reponses.shift();
    return new Response(JSON.stringify(corps), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }) as typeof fetch;
  const client = new ClientOrangeMoney({ urlBase: URL_ORANGE_MONEY.bacASable, idClient: 'i', secretClient: 's', fetcher });
  const fournisseur = new FournisseurOrangeMoney({ client, codeMarchand: CODE_MARCHAND_TEST }, () => midi);
  assert.equal((await fournisseur.creerSession('r1', 1000)).lienPaiement, 'https://sugu.orange-sonatel.com/om');
  assert.equal((await fournisseur.creerSession('r2', 1000)).lienPaiement, 'https://sugu.orange-sonatel.com/court');
  await assert.rejects(fournisseur.creerSession('r3', 1000), ErreurFournisseur);
});

test('notification : 405 hors POST, 503 si Orange Money n\'est pas configuré, sans rien lire', async () => {
  const orange = new FauxOrange();
  const config = { client: orange.client(), codeMarchand: CODE_MARCHAND_TEST };
  const corpsBrut = Buffer.from('{}');
  const repondre = (methode: string, c: typeof config | null, cle: string) =>
    repondreNotificationOrange(sansBase, c, cle, { methode, autorisation: `Basic ${CLE}`, corpsBrut }, sansRemboursement, midi);
  assert.equal((await repondre('GET', config, CLE)).statut, 405);
  assert.equal((await repondre('POST', null, CLE)).statut, 503);
  assert.equal((await repondre('POST', config, '  ')).statut, 503);
  assert.deepEqual(orange.requetes, []);
});

test('notification sans la bonne clé : 401 (Orange abandonne), Orange n\'est même pas interrogé', async () => {
  const orange = new FauxOrange();
  const config = { client: orange.client(), codeMarchand: CODE_MARCHAND_TEST };
  const id = orange.payer('a1b2c3', 2300);
  for (const autorisation of [undefined, '', `Basic ${CLE}x`, `Bearer ${CLE}`, CLE, 'Basic ']) {
    const r = await repondreNotificationOrange(
      sansBase,
      config,
      CLE,
      { methode: 'POST', autorisation, corpsBrut: orange.notification(id) },
      sansRemboursement,
      midi,
    );
    assert.equal(r.statut, 401, String(autorisation));
    assert.equal(r.corps, 'Notification refusée.');
  }
  assert.deepEqual(orange.requetes, []);
});

test('notification authentifiée mais Orange injoignable : 500, pour qu\'Orange la renvoie plus tard', async () => {
  const orange = new FauxOrange();
  const config = { client: orange.client(), codeMarchand: CODE_MARCHAND_TEST };
  const id = orange.payer('a1b2c3', 2300);
  orange.panneRecherche = 503;
  const r = await repondreNotificationOrange(
    sansBase,
    config,
    CLE,
    { methode: 'POST', autorisation: `Basic ${CLE}`, corpsBrut: orange.notification(id) },
    sansRemboursement,
    midi,
  );
  assert.equal(r.statut, 500);
  assert.ok(orange.requetes.includes('GET /api/eWallet/v1/transactions'));
});
