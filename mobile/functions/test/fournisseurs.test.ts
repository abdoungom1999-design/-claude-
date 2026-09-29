import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  corpsWebhook,
  ErreurFournisseur,
  ErreurSignature,
  FournisseurSimule,
  FournisseurWave,
  lireEvenement,
  signer,
  verifierSignature,
} from '../src/fournisseurs';
import { echapper, pagePaiement } from '../src/simulation';

const SECRET = 'secret-de-test';
const maintenant = new Date(Date.UTC(2026, 8, 29, 12));
const corps = corpsWebhook('sim_abc', 'cmd1', true, 2300);

test('signature valide acceptée, événement lu', () => {
  const f = new FournisseurSimule(SECRET, 'https://page');
  const e = f.lireWebhook(Buffer.from(corps), signer(corps, SECRET, maintenant), maintenant);
  assert.deepEqual(e, { sessionId: 'sim_abc', commandeId: 'cmd1', reussi: true, montantFcfa: 2300, devise: 'XOF' });
});

test('signature absente, fausse, d\'un autre secret ou corps modifié : refusée', () => {
  const b = Buffer.from(corps);
  const refuse = (entete: string | undefined, corpsBrut = b) =>
    assert.throws(() => verifierSignature(corpsBrut, entete, SECRET, maintenant), ErreurSignature);
  refuse(undefined);
  refuse('');
  refuse('t=abc,v1=zz');
  refuse(signer(corps, 'autre-secret', maintenant));
  refuse(signer(corps, SECRET, maintenant), Buffer.from(corpsWebhook('sim_abc', 'cmd1', true, 100)));
});

test('signature trop ancienne (rejeu) : refusée ; dans la tolérance : acceptée', () => {
  const b = Buffer.from(corps);
  const ilYa = (s: number) => new Date(maintenant.getTime() - s * 1000);
  verifierSignature(b, signer(corps, SECRET, ilYa(299)), SECRET, maintenant);
  assert.throws(() => verifierSignature(b, signer(corps, SECRET, ilYa(301)), SECRET, maintenant), /expirée/);
});

test('événement d\'échec ou incomplet', () => {
  assert.equal(lireEvenement(Buffer.from(corpsWebhook('s', 'c', false, 2300))).reussi, false);
  assert.throws(() => lireEvenement(Buffer.from('pas du json')), ErreurSignature);
  assert.throws(() => lireEvenement(Buffer.from('{"data":{"id":"s"}}')), ErreurSignature);
});

test('simulation : une session unique par paiement, lien vers la page simulée', async () => {
  const f = new FournisseurSimule(SECRET, 'https://page');
  const a = await f.creerSession();
  const b = await f.creerSession();
  assert.match(a.sessionId, /^sim_[0-9a-f]{24}$/);
  assert.notEqual(a.sessionId, b.sessionId);
  assert.equal(a.lienPaiement, `https://page?session=${a.sessionId}`);
});

test('Wave : session de paiement créée par l\'API Checkout', async () => {
  const appels: { url: string; init: RequestInit }[] = [];
  const faux = (async (url: string, init: RequestInit) => {
    appels.push({ url, init });
    return new Response(JSON.stringify({ id: 'cos_1', wave_launch_url: 'https://pay.wave.com/c/cos_1' }), { status: 200 });
  }) as unknown as typeof fetch;
  const wave = new FournisseurWave('cle-api', SECRET, 'https://retour', faux);
  const session = await wave.creerSession('cmd1', 2300);
  assert.deepEqual(session, { sessionId: 'cos_1', lienPaiement: 'https://pay.wave.com/c/cos_1' });
  assert.equal(appels[0].url, 'https://api.wave.com/v1/checkout/sessions');
  assert.equal((appels[0].init.headers as Record<string, string>).Authorization, 'Bearer cle-api');
  const envoye = JSON.parse(String(appels[0].init.body));
  assert.equal(envoye.amount, '2300');
  assert.equal(envoye.currency, 'XOF');
  assert.equal(envoye.client_reference, 'cmd1');

  await wave.rembourser('cos_1');
  assert.equal(appels[1].url, 'https://api.wave.com/v1/checkout/sessions/cos_1/refund');
});

test('Wave : erreur ou réponse incomplète, sans jamais exposer la clé', async () => {
  const repond = (statut: number, corpsReponse: unknown) =>
    (async () => new Response(JSON.stringify(corpsReponse), { status: statut })) as unknown as typeof fetch;
  await assert.rejects(new FournisseurWave('cle-secrete', SECRET, 'r', repond(401, {})).creerSession('c', 1000), (e: unknown) => {
    assert.ok(e instanceof ErreurFournisseur);
    assert.doesNotMatch(e.message, /cle-secrete/);
    return true;
  });
  await assert.rejects(new FournisseurWave('k', SECRET, 'r', repond(200, { id: 'x' })).creerSession('c', 1000), ErreurFournisseur);
});

test('page simulée : adresses échappées, commande déjà traitée non payable', () => {
  assert.equal(echapper('<script>"&\''), '&#60;script&#62;&#34;&#38;&#39;');
  const html = pagePaiement('sim_1', {
    prixFcfa: 12500, adresseDepart: '<b>Plateau</b>', adresseArrivee: 'Almadies', statut: 'en_attente_paiement', methodePaiement: 'WAVE',
  });
  assert.match(html, /12 500 FCFA/);
  assert.match(html, /<h1>Wave<\/h1>/);
  assert.doesNotMatch(html, /<b>Plateau/);
  assert.match(html, /name="choix" value="payer"/);
  const traitee = pagePaiement('sim_1', { prixFcfa: 1000, adresseDepart: 'a', adresseArrivee: 'b', statut: 'payee', methodePaiement: 'WAVE' });
  assert.doesNotMatch(traitee, /value="payer"/);
  const orange = pagePaiement('sim_1', { prixFcfa: 1000, adresseDepart: 'a', adresseArrivee: 'b', statut: 'en_attente_paiement', methodePaiement: 'ORANGE_MONEY' });
  assert.match(orange, /<h1>Orange Money<\/h1>/);
});
