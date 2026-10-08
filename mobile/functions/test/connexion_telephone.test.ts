import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cleAnnuaire, hoteIdentite, verifierMotDePasseFirebase } from '../src/connexion_telephone';

test('clé d\'annuaire : rôle + numéro tel que saisi (espaces autour retirés), jamais de barre oblique', () => {
  assert.equal(cleAnnuaire('client', '+221771234567'), 'client_+221771234567');
  assert.equal(cleAnnuaire('conducteur', '  77 123 45 67  '), 'conducteur_77 123 45 67');
  assert.equal(cleAnnuaire('client', ''), null);
  assert.equal(cleAnnuaire('client', '   '), null);
  assert.equal(cleAnnuaire('client', '77/123'), null);
  assert.equal(cleAnnuaire('client', '7'.repeat(41)), null);
  assert.equal(cleAnnuaire('client', '7'.repeat(40)), `client_${'7'.repeat(40)}`);
});

test('hôte d\'identification : Google, ou l\'émulateur Auth en test', () => {
  assert.equal(hoteIdentite({}), 'https://identitytoolkit.googleapis.com');
  assert.equal(hoteIdentite({ FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099' }), 'http://127.0.0.1:9099/identitytoolkit.googleapis.com');
});

function reponse(statut: number, corps: unknown = {}): Response {
  return new Response(JSON.stringify(corps), { status: statut, headers: { 'Content-Type': 'application/json' } });
}

test('vérification du mot de passe : requête REST de Firebase Auth, jamais de secret hors de la requête', async () => {
  const appels: { url: string; init: RequestInit }[] = [];
  const fetcher = (async (url: string, init: RequestInit) => {
    appels.push({ url, init });
    return reponse(200, { idToken: 'jeton-a-ne-pas-rendre', localId: 'u1' });
  }) as unknown as typeof fetch;
  const verifier = verifierMotDePasseFirebase('CLE-WEB', fetcher, 'https://identite.test');

  assert.equal(await verifier('awa@test.sn', 'motdepasse'), 'ok');
  assert.equal(appels.length, 1);
  assert.equal(appels[0].url, 'https://identite.test/v1/accounts:signInWithPassword?key=CLE-WEB');
  assert.equal(appels[0].init.method, 'POST');
  assert.deepEqual(JSON.parse(appels[0].init.body as string), { email: 'awa@test.sn', password: 'motdepasse', returnSecureToken: true });
});

test('vérification du mot de passe : identifiants faux = refuse, quelle qu\'en soit la raison', async () => {
  for (const code of [
    'INVALID_PASSWORD',
    'EMAIL_NOT_FOUND',
    'INVALID_LOGIN_CREDENTIALS',
    'INVALID_EMAIL',
    'MISSING_PASSWORD',
    'USER_DISABLED',
    'INVALID_PASSWORD : le détail suit',
  ]) {
    const fetcher = (async () => reponse(400, { error: { code: 400, message: code } })) as unknown as typeof fetch;
    assert.equal(await verifierMotDePasseFirebase('k', fetcher, 'https://x')('a@b.sn', 'p'), 'refuse', code);
  }
});

test('vérification du mot de passe : trop d\'essais côté Firebase = limite', async () => {
  const fetcher = (async () => reponse(400, { error: { message: 'TOO_MANY_ATTEMPTS_TRY_LATER : Access to this account has been temporarily disabled' } })) as unknown as typeof fetch;
  assert.equal(await verifierMotDePasseFirebase('k', fetcher, 'https://x')('a@b.sn', 'p'), 'limite');
});

test('vérification du mot de passe : panne, clé refusée, quota ou réponse illisible = indisponible (jamais « refuse »)', async () => {
  const pannes: (() => Promise<Response>)[] = [
    async () => { throw new Error('réseau coupé'); },
    async () => reponse(403, { error: { message: 'API key not valid' } }),
    async () => reponse(429, { error: { message: 'QUOTA_EXCEEDED' } }),
    async () => reponse(500),
    async () => new Response('pas du json', { status: 502 }),
    async () => reponse(400, { error: { message: 'OPERATION_NOT_ALLOWED' } }),
  ];
  for (const panne of pannes) {
    const fetcher = (async () => panne()) as unknown as typeof fetch;
    assert.equal(await verifierMotDePasseFirebase('k', fetcher, 'https://x')('a@b.sn', 'p'), 'indisponible');
  }
});
