import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { Firestore } from 'firebase-admin/firestore';
import {
  approbationChauffeur,
  COULEURS_EMAIL,
  EMAIL_ACTIVATION_CHAUFFEUR,
  envoyerEmailActivation,
  EXPEDITEUR,
  modeleActivationChauffeur,
  NOM_SECRET_RESEND,
  prenomAffiche,
  SUJET_ACTIVATION,
  URL_ANDROID,
  URL_APP,
  type ComptesEmail,
} from '../src/email_activation';
import { ClientResend, DELAI_RESEND_MS, ErreurResend, URL_RESEND, type CourrielResend, type EnvoiCourriel } from '../src/email_resend';

const CLE = 're_clé_de_test_0123456789';
const COURRIEL: CourrielResend = {
  from: EXPEDITEUR,
  to: ['moussa@exemple.sn'],
  subject: 'Sujet',
  html: '<p>Bonjour</p>',
  text: 'Bonjour',
  reply_to: 'contact@sprintvtc.sn',
};

// --- Faux Resend (fetch) ---------------------------------------------------------------------

type Appel = { url: string; method: string; headers: Record<string, string>; body: string };
function fauxFetch(reponse: { ok: boolean; status: number; json?: () => Promise<unknown> } | Error | 'suspendu') {
  const appels: Appel[] = [];
  const appel = (url: string, init: { method: string; headers: Record<string, string>; body: string; signal: AbortSignal }) => {
    appels.push({ url, method: init.method, headers: init.headers, body: init.body });
    if (reponse === 'suspendu') {
      return new Promise<never>((_, rejeter) => {
        init.signal.addEventListener('abort', () => rejeter(Object.assign(new Error('aborted'), { name: 'AbortError' })));
      });
    }
    if (reponse instanceof Error) return Promise.reject(reponse);
    return Promise.resolve({ ok: reponse.ok, status: reponse.status, json: reponse.json ?? (async () => ({})) });
  };
  return { appel, appels };
}

// --- Client Resend ---------------------------------------------------------------------------

test('Resend : le message part en POST vers l\'API, avec la clé, la clé d\'idempotence et le corps tel quel', async () => {
  const f = fauxFetch({ ok: true, status: 200, json: async () => ({ id: 'msg_123' }) });
  const resultat = await new ClientResend(CLE, f.appel).envoyer(COURRIEL, 'activation-chauffeur-u1');

  assert.deepEqual(resultat, { id: 'msg_123' });
  assert.equal(f.appels.length, 1);
  const a = f.appels[0];
  assert.equal(a.url, URL_RESEND);
  assert.equal(a.url, 'https://api.resend.com/emails');
  assert.equal(a.method, 'POST');
  assert.equal(a.headers.Authorization, `Bearer ${CLE}`);
  assert.equal(a.headers['Content-Type'], 'application/json');
  assert.equal(a.headers['Idempotency-Key'], 'activation-chauffeur-u1');
  assert.ok(a.headers['User-Agent']);
  assert.deepEqual(JSON.parse(a.body), COURRIEL);
});

test('Resend : espaces, retours à la ligne et caractères invisibles collés avec la clé sont retirés', async () => {
  const f = fauxFetch({ ok: true, status: 200, json: async () => ({ id: 'm' }) });
  await new ClientResend(` \n${CLE}​ \r\n`, f.appel).envoyer(COURRIEL, 'k');
  assert.equal(f.appels[0].headers.Authorization, `Bearer ${CLE}`);
});

test('Resend : sans clé, rien n\'est envoyé et le code le dit', async () => {
  const f = fauxFetch({ ok: true, status: 200 });
  for (const vide of ['', '   ', '\n​']) {
    const client = new ClientResend(vide, f.appel);
    assert.equal(client.disponible, false);
    await assert.rejects(client.envoyer(COURRIEL, 'k'), (e: unknown) => e instanceof ErreurResend && e.code === 'resend/cle_absente');
  }
  assert.equal(f.appels.length, 0);
});

test('Resend : refus de l\'API (401, 403, 422, 429, 500) : code précis, nom d\'erreur de Resend gardé, aucune clé dans l\'erreur', async () => {
  for (const [statut, nom] of [
    [401, 'restricted_api_key'],
    [403, 'validation_error'],
    [422, 'validation_error'],
    [429, 'rate_limit_exceeded'],
    [500, 'application_error'],
  ] as const) {
    const f = fauxFetch({ ok: false, status: statut, json: async () => ({ name: nom, message: `refusé avec ${CLE}`, statusCode: statut }) });
    await assert.rejects(new ClientResend(CLE, f.appel).envoyer(COURRIEL, 'k'), (e: unknown) => {
      assert.ok(e instanceof ErreurResend);
      assert.equal(e.code, `resend/${statut}`);
      assert.equal(e.nomResend, nom);
      // Le message de Resend (qui pourrait citer la clé) n'est jamais repris.
      assert.ok(!JSON.stringify(e).includes(CLE) && !e.message.includes(CLE) && !String(e.stack).includes(CLE));
      return true;
    });
  }
});

test('Resend : réponse d\'erreur sans JSON, réponse sans identifiant, réseau coupé, délai dépassé', async () => {
  const sansJson = fauxFetch({ ok: false, status: 502, json: async () => Promise.reject(new SyntaxError('x')) });
  await assert.rejects(new ClientResend(CLE, sansJson.appel).envoyer(COURRIEL, 'k'), (e: unknown) => e instanceof ErreurResend && e.code === 'resend/502');

  const sansId = fauxFetch({ ok: true, status: 200, json: async () => ({}) });
  await assert.rejects(new ClientResend(CLE, sansId.appel).envoyer(COURRIEL, 'k'), (e: unknown) => e instanceof ErreurResend && e.code === 'resend/reponse');

  const coupe = fauxFetch(new TypeError('fetch failed'));
  await assert.rejects(new ClientResend(CLE, coupe.appel).envoyer(COURRIEL, 'k'), (e: unknown) => e instanceof ErreurResend && e.code === 'resend/reseau');

  const suspendu = fauxFetch('suspendu');
  await assert.rejects(new ClientResend(CLE, suspendu.appel, 20).envoyer(COURRIEL, 'k'), (e: unknown) => e instanceof ErreurResend && e.code === 'resend/delai');
  assert.equal(DELAI_RESEND_MS, 10_000);
});

// --- Modèle d'e-mail -------------------------------------------------------------------------

test('Modèle : noir Onyx et orange, objet, prénom, trois étapes, bouton et adresse de contact', () => {
  const m = modeleActivationChauffeur('Moussa');
  assert.equal(m.sujet, SUJET_ACTIVATION);
  assert.equal(SUJET_ACTIVATION, 'Bienvenue chez SPRINT : votre compte chauffeur est activé');

  for (const couleur of [COULEURS_EMAIL.fond, COULEURS_EMAIL.carte, COULEURS_EMAIL.orange]) assert.ok(m.html.includes(couleur), couleur);
  assert.equal(COULEURS_EMAIL.fond, '#0B0B0C');
  assert.match(COULEURS_EMAIL.orange, /^#FF[0-9A-F]{4}$/);
  assert.ok(m.html.includes('Félicitations Moussa, votre compte chauffeur est activé'));
  assert.ok(m.html.includes(`href="${URL_APP}"`) && m.html.includes('Ouvrir SPRINT'));
  assert.ok(m.html.includes(URL_ANDROID));
  assert.ok(m.html.includes('contact@sprintvtc.sn'));
  assert.match(m.html, /^<!DOCTYPE html>/);
  // Aucune image distante (bloquée par beaucoup de messageries) ni script.
  assert.ok(!/<img|<script|<link|url\(/i.test(m.html));

  assert.ok(m.texte.includes('Félicitations Moussa'));
  for (const etape of ['1. ', '2. ', '3. ']) assert.ok(m.texte.includes(etape), etape);
  assert.ok(m.texte.includes(URL_APP) && m.texte.includes('contact@sprintvtc.sn'));
  assert.ok(!/<[a-z]/i.test(m.texte), 'la version texte ne contient aucune balise');
});

test('Modèle : sans prénom, un titre neutre ; un prénom piégé est neutralisé', () => {
  assert.ok(modeleActivationChauffeur(null).html.includes('Félicitations, votre compte chauffeur est activé'));
  const piege = modeleActivationChauffeur('<script>alert(1)</script>"&');
  assert.ok(!piege.html.includes('<script>alert'));
  assert.ok(piege.html.includes('&lt;script&gt;alert(1)&lt;/script&gt;&quot;&amp;'));
});

test('prenomAffiche : prénom du profil, sinon premier mot du nom, borné et nettoyé', () => {
  assert.equal(prenomAffiche({ prenom: 'Moussa', nom: 'Moussa Diop' }), 'Moussa');
  assert.equal(prenomAffiche({ nom: 'Awa Fall' }), 'Awa');
  assert.equal(prenomAffiche({ prenom: '  ', nom: 'Ibou Sarr' }), 'Ibou');
  assert.equal(prenomAffiche({ prenom: 42, nom: '' }), null);
  assert.equal(prenomAffiche({}), null);
  assert.equal(prenomAffiche({ prenom: 'x'.repeat(100) })?.length, 40);
  assert.equal(prenomAffiche({ prenom: 'Mou\nssa\u0000' }), 'Moussa');
});

// --- Quand envoyer ----------------------------------------------------------------------------

test('approbationChauffeur : seulement le passage à « valide » d\'un chauffeur', () => {
  const chauffeur = (statutValidation?: string) => ({ role: 'conducteur', ...(statutValidation ? { statutValidation } : {}) });
  assert.equal(approbationChauffeur(chauffeur('en_attente'), chauffeur('valide')), true);
  assert.equal(approbationChauffeur(chauffeur('rejete'), chauffeur('valide')), true);
  assert.equal(approbationChauffeur(chauffeur(), chauffeur('valide')), true);
  assert.equal(approbationChauffeur(undefined, chauffeur('valide')), true);
  // Déjà validé : une autre modification du profil ne renvoie rien.
  assert.equal(approbationChauffeur(chauffeur('valide'), chauffeur('valide')), false);
  assert.equal(approbationChauffeur(chauffeur('valide'), { ...chauffeur('valide'), telephone: '+221' }), false);
  // Autres statuts, autres rôles.
  assert.equal(approbationChauffeur(chauffeur('en_attente'), chauffeur('rejete')), false);
  assert.equal(approbationChauffeur(chauffeur('valide'), chauffeur('en_attente')), false);
  assert.equal(approbationChauffeur({ role: 'client' }, { role: 'client', statutValidation: 'valide' }), false);
  assert.equal(approbationChauffeur({ role: 'admin' }, { role: 'admin', statutValidation: 'valide' }), false);
  assert.equal(approbationChauffeur(chauffeur('en_attente'), undefined), false);
});

// --- Faux Firestore / Auth / envoi -----------------------------------------------------------

function fauxDb(profil: Record<string, unknown> | undefined, options: { echecMarque?: boolean } = {}) {
  const ecritures: Record<string, unknown>[] = [];
  const lectures: string[] = [];
  const db = {
    collection: (nom: string) => ({
      doc: (id: string) => ({
        get: async () => {
          lectures.push(`${nom}/${id}`);
          return { data: () => profil };
        },
        update: async (valeurs: Record<string, unknown>) => {
          if (options.echecMarque) throw new Error('écriture refusée');
          ecritures.push(valeurs);
        },
      }),
    }),
  } as unknown as Firestore;
  return { db, ecritures, lectures };
}

const comptes = (adresse: string | null): ComptesEmail => ({ adresseVerifiee: async () => adresse });

function fauxEnvoi(resultat: { id: string } | Error) {
  const envois: { courriel: CourrielResend; cle: string }[] = [];
  const envoi: EnvoiCourriel = {
    envoyer: async (courriel, cle) => {
      envois.push({ courriel, cle });
      if (resultat instanceof Error) throw resultat;
      return resultat;
    },
  };
  return { envoi, envois };
}

const AVANT = { role: 'conducteur', statutValidation: 'en_attente' };
const APRES = { role: 'conducteur', statutValidation: 'valide', nom: 'Moussa Diop', prenom: 'Moussa', email: 'profil@exemple.sn' };

test('Envoi : approbation d\'un chauffeur : expéditeur SPRINT, adresse VÉRIFIÉE de Firebase Auth, réponse à contact@, marque posée', async () => {
  const { db, ecritures } = fauxDb(APRES);
  const { envoi, envois } = fauxEnvoi({ id: 'msg_42' });

  const r = await envoyerEmailActivation({ db, comptes: comptes('auth@exemple.sn'), envoi }, 'uid123', AVANT, APRES);

  assert.deepEqual(r, { envoye: true, id: 'msg_42' });
  assert.equal(envois.length, 1);
  const { courriel, cle } = envois[0];
  assert.equal(courriel.from, 'SPRINT <contact@sprintvtc.sn>');
  assert.deepEqual(courriel.to, ['auth@exemple.sn'], 'l\'adresse vient de Firebase Auth, pas du profil modifiable');
  assert.equal(courriel.reply_to, 'contact@sprintvtc.sn');
  assert.equal(courriel.subject, SUJET_ACTIVATION);
  assert.ok(courriel.html.includes('Félicitations Moussa'));
  assert.equal(cle, 'activation-chauffeur-uid123');
  assert.equal(ecritures.length, 1);
  assert.equal(ecritures[0].emailActivationId, 'msg_42');
  assert.ok(ecritures[0].emailActivationEnvoyeLe, 'la date d\'envoi est posée par le serveur');
});

test('Envoi : ce qui n\'est pas une approbation ne lit rien et n\'envoie rien', async () => {
  for (const [avant, apres] of [
    [{ role: 'conducteur', statutValidation: 'valide' }, APRES],
    [AVANT, { ...APRES, statutValidation: 'rejete' }],
    [{ role: 'client' }, { role: 'client', statutValidation: 'valide' }],
  ] as const) {
    const { db, lectures } = fauxDb(APRES);
    const { envoi, envois } = fauxEnvoi({ id: 'x' });
    const r = await envoyerEmailActivation({ db, comptes: comptes('a@b.sn'), envoi }, 'u', avant, apres);
    assert.deepEqual(r, { envoye: false, raison: 'pas_une_approbation' });
    assert.equal(envois.length + lectures.length, 0);
  }
});

test('Envoi : une seule fois par chauffeur (marque déjà posée) ; dossier changé depuis ; compte suspendu ou banni', async () => {
  const cas: [string, Record<string, unknown>, string][] = [
    ['marque déjà posée', { ...APRES, emailActivationEnvoyeLe: new Date() }, 'deja_envoye'],
    ['dossier rejeté entre-temps', { ...APRES, statutValidation: 'rejete' }, 'dossier_non_valide'],
    ['plus un chauffeur', { ...APRES, role: 'client' }, 'dossier_non_valide'],
    ['compte suspendu', { ...APRES, statutCompte: 'suspendu' }, 'compte_bloque'],
    ['compte banni', { ...APRES, statutCompte: 'banni' }, 'compte_bloque'],
  ];
  for (const [nom, profil, raison] of cas) {
    const { db, ecritures } = fauxDb(profil);
    const { envoi, envois } = fauxEnvoi({ id: 'x' });
    const r = await envoyerEmailActivation({ db, comptes: comptes('a@b.sn'), envoi }, 'u', AVANT, APRES);
    assert.deepEqual(r, { envoye: false, raison }, nom);
    assert.equal(envois.length + ecritures.length, 0, nom);
  }
});

test('Envoi : adresse non vérifiée ou absente chez Firebase Auth : rien n\'est envoyé', async () => {
  const { db, ecritures } = fauxDb(APRES);
  const { envoi, envois } = fauxEnvoi({ id: 'x' });
  const r = await envoyerEmailActivation({ db, comptes: comptes(null), envoi }, 'u', AVANT, APRES);
  assert.deepEqual(r, { envoye: false, raison: 'email_non_verifie' });
  assert.equal(envois.length + ecritures.length, 0);
});

test('Envoi : Resend refuse ou ne répond pas : jamais d\'exception, code consigné, RIEN n\'est marqué envoyé (un nouvel essai reste possible)', async () => {
  for (const erreur of [new ErreurResend('resend/422', 'validation_error'), new ErreurResend('resend/reseau'), new ErreurResend('resend/delai'), new Error('inattendu')]) {
    const { db, ecritures } = fauxDb(APRES);
    const { envoi } = fauxEnvoi(erreur);
    const r = await envoyerEmailActivation({ db, comptes: comptes('a@b.sn'), envoi }, 'u', AVANT, APRES);
    assert.equal(r.envoye, false);
    assert.ok(!r.envoye && r.raison === 'echec');
    assert.equal(!r.envoye && r.code, erreur instanceof ErreurResend ? erreur.code : 'resend/inconnu');
    assert.equal(ecritures.length, 0);
  }
});

test('Envoi : si la marque ne peut pas être écrite, l\'e-mail est parti et le résultat le dit', async () => {
  const { db } = fauxDb(APRES, { echecMarque: true });
  const { envoi, envois } = fauxEnvoi({ id: 'msg_9' });
  const r = await envoyerEmailActivation({ db, comptes: comptes('a@b.sn'), envoi }, 'u', AVANT, APRES);
  assert.deepEqual(r, { envoye: true, id: 'msg_9' });
  assert.equal(envois.length, 1);
});

// --- Réglages et câblage ---------------------------------------------------------------------

test('OUVERT sur la demande du client (lot 149) : la fonction est liée au secret RESEND_API_KEY, qui n\'est déclaré que si l\'envoi est ouvert', () => {
  assert.equal(EMAIL_ACTIVATION_CHAUFFEUR, true, 'ouvert le 20 novembre 2026 (lot 149), après création de RESEND_API_KEY par le client');
  assert.equal(NOM_SECRET_RESEND, 'RESEND_API_KEY');
  assert.equal(EXPEDITEUR, 'SPRINT <contact@sprintvtc.sn>');

  const index = readFileSync(join(__dirname, '../../src/index.ts'), 'utf8');
  assert.match(index, /const cleResend = EMAIL_ACTIVATION_CHAUFFEUR \? defineSecret\(NOM_SECRET_RESEND\) : null;/, 'le secret n\'est déclaré que si l\'envoi est ouvert');
  assert.match(index, /export const activationChauffeurEmail = cleResend\s*\n\s*\? onDocumentUpdated\(\{ document: 'users\/\{uid\}', secrets: \[cleResend\] \}/, 'la fonction n\'existe que si le secret existe');
  assert.match(index, /\n  : undefined;/);
});

test('Aucune clé Resend écrite dans le code', () => {
  for (const fichier of ['email_resend.ts', 'email_activation.ts', 'index.ts']) {
    const source = readFileSync(join(__dirname, '../../src', fichier), 'utf8');
    assert.ok(!/\bre_[A-Za-z0-9_]{12,}/.test(source), fichier);
  }
});
