import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  ClientOrangeMoney,
  ErreurNotificationOrange,
  ErreurOrangeMoney,
  lireNotification,
  URL_ORANGE_MONEY,
} from '../src/orange_money';

// Faux identifiants : ils ne doivent jamais apparaître dans un message d'erreur.
const ID = 'id-client-de-test';
const SECRET = 'secret-client-de-test-ne-pas-afficher';

interface Appel {
  url: string;
  init: RequestInit;
}

/** Faux Orange : rend les réponses dans l'ordre et garde chaque requête. */
function fauxOrange(reponses: Array<Response | Error>) {
  const appels: Appel[] = [];
  const fetcher = (async (url: string | URL | Request, init?: RequestInit) => {
    appels.push({ url: String(url), init: init ?? {} });
    const suivante = reponses.shift();
    if (suivante === undefined) throw new Error('requête inattendue');
    if (suivante instanceof Error) throw suivante;
    return suivante;
  }) as typeof fetch;
  return { appels, fetcher };
}

const json = (corps: unknown, status = 200, type = 'application/json') =>
  new Response(JSON.stringify(corps), { status, headers: { 'Content-Type': type } });

const jeton = (valeur: string, expiresIn = 3600) => json({ access_token: valeur, token_type: 'bearer', expires_in: expiresIn });

function client(
  reponses: Array<Response | Error>,
  { urlBase = URL_ORANGE_MONEY.bacASable, horloge = () => 0 }: { urlBase?: string; horloge?: () => number } = {},
) {
  const faux = fauxOrange(reponses);
  return { ...faux, om: new ClientOrangeMoney({ urlBase, idClient: ID, secretClient: SECRET, fetcher: faux.fetcher, maintenant: horloge }) };
}

const entete = (appel: Appel, nom: string) => (appel.init.headers as Record<string, string>)[nom];
const corpsJson = (appel: Appel) => JSON.parse(String(appel.init.body)) as Record<string, unknown>;

test('jeton : formulaire « client credentials », réutilisé, renouvelé une minute avant son expiration', async () => {
  let t = 0;
  const { om, appels } = client([jeton('A', 3600), jeton('B', 3600)], { horloge: () => t });

  assert.equal(await om.jeton(), 'A');
  assert.equal(appels[0].url, 'https://api.sandbox.orange-sonatel.com/oauth/v1/token');
  assert.equal(appels[0].init.method, 'POST');
  assert.equal(entete(appels[0], 'Content-Type'), 'application/x-www-form-urlencoded');
  const formulaire = new URLSearchParams(String(appels[0].init.body));
  assert.deepEqual(Object.fromEntries(formulaire), { client_id: ID, client_secret: SECRET, grant_type: 'client_credentials' });

  t = 3539 * 1000;
  assert.equal(await om.jeton(), 'A', 'encore valable : pas de nouvelle demande');
  assert.equal(appels.length, 1);
  t = 3541 * 1000;
  assert.equal(await om.jeton(), 'B', 'moins d\'une minute avant l\'expiration : renouvelé');
  assert.equal(appels.length, 2);
});

test('un 401 fait renouveler le jeton une seule fois et rejouer la requête ; un second 401 est une erreur', async () => {
  const succes = client([jeton('A'), json({}, 401), jeton('B'), json({ status: 'SUCCESS' })]);
  assert.equal(await succes.om.statutTransaction('MP220928.1029.C58502'), 'SUCCESS');
  assert.equal(entete(succes.appels[1], 'Authorization'), 'Bearer A');
  assert.equal(entete(succes.appels[3], 'Authorization'), 'Bearer B');

  const echec = client([jeton('A'), json({}, 401), jeton('B'), json({}, 401)]);
  await assert.rejects(echec.om.statutTransaction('MP220928.1029.C58502'), (e: unknown) => e instanceof ErreurOrangeMoney && e.statutHttp === 401);
  assert.equal(echec.appels.length, 4);
});

test('QR code : requête conforme à la spécification, liens Max It et Orange Money lus', async () => {
  const { om, appels } = client([
    jeton('A'),
    json({
      qrId: 'dFhuPYHJi4BCoCx64L2s',
      deepLinks: { MAXIT: 'https://sugu.orange-sonatel.com/mp/1', OM: 'https://sugu.orange-sonatel.com/mp/2' },
      shortLink: 'https://s.orange-sonatel.com/aBc123',
      qrCode: 'iVBORw0KGgo=',
      validity: 900,
      validFor: { startDateTime: '2026-10-29T09:00:00Z', endDateTime: '2026-10-29T09:15:00Z' },
    }),
  ]);
  const qr = await om.genererQrCode({
    codeMarchand: '123456',
    nomMarchand: 'Sprint',
    montantFcfa: 1500,
    reference: 'commande-1',
    urlNotification: 'https://exemple.test/notification',
    urlSucces: 'https://exemple.test/succes',
    urlAnnulation: 'https://exemple.test/annulation',
    metadonnees: { commande: 'commande-1' },
  });

  const appel = appels[1];
  assert.equal(appel.url, 'https://api.sandbox.orange-sonatel.com/api/eWallet/v4/qrcode');
  assert.equal(appel.init.method, 'POST');
  assert.equal(entete(appel, 'Authorization'), 'Bearer A');
  assert.equal(entete(appel, 'Content-Type'), 'application/json');
  assert.equal(entete(appel, 'X-Callback-Url'), 'https://exemple.test/notification');
  assert.deepEqual(corpsJson(appel), {
    code: '123456',
    name: 'Sprint',
    amount: { value: 1500, unit: 'XOF' },
    reference: 'commande-1',
    validity: 900,
    callbackSuccessUrl: 'https://exemple.test/succes',
    callbackCancelUrl: 'https://exemple.test/annulation',
    metadata: { commande: 'commande-1' },
    restrictions: { isSingleUse: true },
  });
  assert.deepEqual(qr, {
    qrId: 'dFhuPYHJi4BCoCx64L2s',
    lienMaxIt: 'https://sugu.orange-sonatel.com/mp/1',
    lienOrangeMoney: 'https://sugu.orange-sonatel.com/mp/2',
    lienCourt: 'https://s.orange-sonatel.com/aBc123',
    imageBase64: 'iVBORw0KGgo=',
    validiteSecondes: 900,
    finValidite: '2026-10-29T09:15:00Z',
  });
});

test('QR code : sans adresse de notification, pas d\'en-tête ; ancien champ « deepLink » accepté ; réponse vide refusée', async () => {
  const { om, appels } = client([jeton('A'), json({ deepLink: 'https://sugu.orange-sonatel.com/mp/3' }), json({ qrId: 'x' })]);
  const qr = await om.genererQrCode({ codeMarchand: '123456', nomMarchand: 'Sprint', montantFcfa: 300, reference: 'r' });
  assert.equal(entete(appels[1], 'X-Callback-Url'), undefined);
  assert.equal(corpsJson(appels[1]).metadata, undefined);
  assert.equal(qr.lienMaxIt, 'https://sugu.orange-sonatel.com/mp/3');
  await assert.rejects(
    om.genererQrCode({ codeMarchand: '123456', nomMarchand: 'Sprint', montantFcfa: 300, reference: 'r' }),
    /sans QR code ni lien de paiement/,
  );
});

test('QR code : demandes invalides refusées avant tout appel à Orange', async () => {
  const { om, appels } = client([]);
  const base = { codeMarchand: '123456', nomMarchand: 'Sprint', montantFcfa: 1500, reference: 'r' };
  const invalides = [
    { ...base, codeMarchand: '12345' },
    { ...base, codeMarchand: '1234567' },
    { ...base, nomMarchand: ' ' },
    { ...base, montantFcfa: 1500.5 },
    { ...base, montantFcfa: 0 },
    { ...base, reference: '' },
    { ...base, validiteSecondes: 86401 },
    { ...base, validiteSecondes: 0 },
    { ...base, urlNotification: 'http://exemple.test/notification' },
    { ...base, urlSucces: 'http://exemple.test/succes' },
    { ...base, metadonnees: Object.fromEntries(Array.from({ length: 11 }, (_, i) => [`c${i}`, 'v'])) },
  ];
  for (const demande of invalides) {
    await assert.rejects(om.genererQrCode(demande), ErreurOrangeMoney, JSON.stringify(demande));
  }
  assert.equal(appels.length, 0);
});

test('erreurs d\'Orange : statut, code et détail lisibles, jamais d\'identifiant ni de jeton', async () => {
  const probleme = client([
    jeton('jeton-secret'),
    json(
      {
        type: 'https://developers.orange-sonatel.com/documentation/errors/bad-request',
        title: 'Bad Request',
        status: '400',
        code: '2000',
        detail: 'Customer account does not exist',
        instance: '/api/eWallet/v4/qrcode',
        violations: [{ field: 'code', message: 'must match "^\\d{6}$"' }],
      },
      400,
      'application/problem+json',
    ),
  ]);
  const erreur = await probleme.om
    .genererQrCode({ codeMarchand: '123456', nomMarchand: 'Sprint', montantFcfa: 1500, reference: 'r' })
    .catch((e: unknown) => e);
  assert.ok(erreur instanceof ErreurOrangeMoney);
  assert.equal(erreur.statutHttp, 400);
  assert.equal(erreur.code, '2000');
  assert.match(erreur.message, /répondu 400 \(code 2000\) : Customer account does not exist/);
  assert.match(erreur.message, /code : must match/);

  const refus = client([json({ error: 'invalid_client', error_description: 'Bad client credentials' }, 401)]);
  const erreurJeton = await refus.om.jeton().catch((e: unknown) => e);
  assert.ok(erreurJeton instanceof ErreurOrangeMoney);
  assert.match(erreurJeton.message, /401 \(code invalid_client\) : Bad client credentials/);

  const quota = client([jeton('A'), json({ title: 'Too Many Requests', status: '429', code: '9' }, 429, 'application/problem+json')]);
  await assert.rejects(quota.om.clePublique(), (e: unknown) => e instanceof ErreurOrangeMoney && e.statutHttp === 429 && e.code === '9');

  const coupure = client([new TypeError('fetch failed')]);
  await assert.rejects(coupure.om.jeton(), /Orange Money injoignable : fetch failed/);

  for (const message of [erreur.message, erreurJeton.message]) {
    for (const secret of [ID, SECRET, 'jeton-secret']) assert.ok(!message.includes(secret), `« ${secret} » dans « ${message} »`);
  }
});

test('statut d\'une transaction : identifiant contrôlé et encodé, statut inconnu refusé', async () => {
  const { om, appels } = client([jeton('A'), json({ status: 'PENDING' }), json({ status: 'BIZARRE' })]);
  await assert.rejects(om.statutTransaction('MP22/../x'), /Identifiant de transaction invalide/);
  assert.equal(appels.length, 0);
  assert.equal(await om.statutTransaction('MP220928.1029.C58502'), 'PENDING');
  assert.equal(appels[1].url, 'https://api.sandbox.orange-sonatel.com/api/eWallet/v1/transactions/MP220928.1029.C58502/status');
  assert.equal(appels[1].init.method, 'GET');
  assert.equal(appels[1].init.body, undefined);
  await assert.rejects(om.statutTransaction('MP220928.1029.C58502'), /Statut de transaction inconnu/);
});

test('adresse de notification : HTTPS et clé longue exigés, enregistrement conforme, liste lue sans la clé', async () => {
  const cle = 'k'.repeat(48);
  const { om, appels } = client([
    jeton('A'),
    json({ code: '123456', name: 'Sprint', callbackUrl: 'https://exemple.test/notification' }, 201),
    json([{ code: '123456', name: 'Sprint', callbackUrl: 'https://exemple.test/notification' }, { code: '654321' }]),
  ]);
  await assert.rejects(om.enregistrerNotification({ codeMarchand: '123456', nomMarchand: 'Sprint', url: 'http://x.test', cleApi: cle }), /HTTPS/);
  await assert.rejects(om.enregistrerNotification({ codeMarchand: '123456', nomMarchand: 'Sprint', url: 'https://x.test', cleApi: 'courte' }), /trop courte/);
  assert.equal(appels.length, 0);

  await om.enregistrerNotification({ codeMarchand: '123456', nomMarchand: 'Sprint', url: 'https://exemple.test/notification', cleApi: cle });
  assert.equal(appels[1].url, 'https://api.sandbox.orange-sonatel.com/api/notification/v1/merchantcallback');
  assert.deepEqual(corpsJson(appels[1]), { code: '123456', name: 'Sprint', callbackUrl: 'https://exemple.test/notification', apiKey: cle });

  assert.deepEqual(await om.notificationsEnregistrees('123456'), [
    { codeMarchand: '123456', nom: 'Sprint', url: 'https://exemple.test/notification' },
  ]);
  assert.equal(appels[2].url, 'https://api.sandbox.orange-sonatel.com/api/notification/v1/merchantcallback?code=123456');
});

test('numéros de test : bac à sable seulement, nombre demandé par type', async () => {
  const production = client([], { urlBase: URL_ORANGE_MONEY.production });
  await assert.rejects(production.om.cartesSimDeTest(), /bac à sable seulement/);
  assert.equal(production.appels.length, 0);

  const { om, appels } = client([
    jeton('A'),
    json([
      { msisdn: '771234567', pinCode: '1234', type: 'CUSTOMER', grade: 'FULL', expiresAt: '2026-11-29T00:00:00Z' },
      { msisdn: '781234567', pinCode: '4321', type: 'MERCHANT' },
      { type: 'CUSTOMER' },
    ]),
  ]);
  const cartes = await om.cartesSimDeTest({ clients: 1, marchands: 1 });
  assert.equal(appels[1].url, 'https://api.sandbox.orange-sonatel.com/api/assignments/v1/partner/sim-cards?nbCustomers=1&nbMerchants=1&nbRetailers=0');
  assert.deepEqual(cartes, [
    { numero: '771234567', codePin: '1234', type: 'CUSTOMER', expireLe: '2026-11-29T00:00:00Z' },
    { numero: '781234567', codePin: '4321', type: 'MERCHANT', expireLe: undefined },
  ]);
});

test('clé publique RSA lue ; identifiants absents refusés dès la création du client', async () => {
  const { om } = client([jeton('A'), json({ key: 'MIIBIjANBg', keyId: '5f2b1c9a', keySize: 2048, keyType: 'RSA' })]);
  assert.deepEqual(await om.clePublique(), { cle: 'MIIBIjANBg', idCle: '5f2b1c9a', tailleBits: 2048 });
  assert.throws(() => new ClientOrangeMoney({ urlBase: URL_ORANGE_MONEY.bacASable, idClient: '', secretClient: SECRET }), ErreurOrangeMoney);
  assert.throws(() => new ClientOrangeMoney({ urlBase: URL_ORANGE_MONEY.bacASable, idClient: ID, secretClient: '' }), ErreurOrangeMoney);
});

test('notification : clé vérifiée, contenu contrôlé ; seule la relecture du statut fera foi', () => {
  const cle = 'une-longue-cle-partagee-de-notification-0123456789';
  const corps = Buffer.from(
    JSON.stringify({
      amount: { value: 1500, unit: 'XOF' },
      partner: { idType: 'CODE', id: '123456' },
      customer: { idType: 'MSISDN', id: '771234567' },
      reference: 'commande-1',
      type: 'MERCHANT_PAYMENT',
      channel: 'API',
      transactionId: 'MP220928.1029.C58502',
      paymentMethod: 'QRCODE',
      status: 'SUCCESS',
    }),
  );
  assert.deepEqual(lireNotification(`Basic ${cle}`, corps, cle), {
    transactionId: 'MP220928.1029.C58502',
    reference: 'commande-1',
    statut: 'SUCCESS',
    montantFcfa: 1500,
    codeMarchand: '123456',
    type: 'MERCHANT_PAYMENT',
  });

  for (const autorisation of [undefined, '', `Basic ${cle}x`, `Bearer ${cle}`, cle, 'Basic autre-cle']) {
    assert.throws(() => lireNotification(autorisation, corps, cle), ErreurNotificationOrange, String(autorisation));
  }
  assert.throws(() => lireNotification(`Basic ${cle}`, corps, ''), /non configurée/);

  const variante = (modif: Record<string, unknown>) => Buffer.from(JSON.stringify({ ...JSON.parse(corps.toString()), ...modif }));
  assert.throws(() => lireNotification(`Basic ${cle}`, Buffer.from('{pas du json'), cle), /illisible/);
  assert.throws(() => lireNotification(`Basic ${cle}`, variante({ status: 'PENDING' }), cle), /Statut/);
  assert.throws(() => lireNotification(`Basic ${cle}`, variante({ transactionId: 'MP/../x' }), cle), /Transaction/);
  assert.throws(() => lireNotification(`Basic ${cle}`, variante({ amount: { value: 0, unit: 'XOF' } }), cle), /Montant/);
  assert.throws(() => lireNotification(`Basic ${cle}`, variante({ type: undefined }), cle), /Type/);
  assert.equal(lireNotification(`Basic ${cle}`, variante({ status: 'FAILED' }), cle).statut, 'FAILED');
});
