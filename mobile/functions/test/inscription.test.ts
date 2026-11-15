// Tunnel d'inscription (validation du téléphone, bienvenue) : règles pures et état « fermé ».
// La partie base de données est dans inscription.emulateur.test.ts (npm run test:emulateur).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { HttpsError } from 'firebase-functions/v2/https';
import {
  ADRESSE_SUPPORT,
  BIENVENUE_AUTOMATIQUE,
  courrielBienvenue,
  declencherBienvenue,
  EMAIL_BIENVENUE,
  messageBienvenue,
  NOUVEAUX_COMPTES_DEPUIS,
  prenomPour,
  telephoneE164,
  validerTelephone,
  VALIDATION_TELEPHONE,
  type ComptesAuth,
  type VerifierJetonTelephone,
} from '../src/inscription';

// Le test compilé vit dans functions/lib/test : trois niveaux plus haut, le dossier mobile/.
const racine = path.join(__dirname, '..', '..', '..');
const source = (fichier: string) => readFileSync(path.join(racine, fichier), 'utf8');

const profil = (champs: Record<string, unknown>) => ({ get: (c: string) => champs[c] });

test('FERMÉ par défaut : la publication qui apporte le tunnel ne change rien pour personne', () => {
  assert.equal(VALIDATION_TELEPHONE, 'fermee');
  assert.equal(BIENVENUE_AUTOMATIQUE, false);
  assert.equal(EMAIL_BIENVENUE, false);
  // Avant l'ouverture, aucun compte n'est « nouveau » (la date est lointaine).
  assert.ok(NOUVEAUX_COMPTES_DEPUIS.getTime() > Date.UTC(2090, 0, 1));
});

test('mêmes réglages dans l\'app (un écart ouvrirait l\'un sans l\'autre)', () => {
  const app = source('lib/features/auth/data/reglage_inscription.dart');
  assert.match(app, /validationTelephone\s*=\s*EtatValidationTelephone\.fermee/);
  assert.match(app, /bienvenueAutomatique\s*=\s*false/);
  const depuis = app.match(/nouveauxComptesDepuis\s*=\s*DateTime\.utc\((\d+),\s*(\d+),\s*(\d+)\)/);
  assert.ok(depuis, 'date des nouveaux comptes introuvable dans l\'app');
  const dateApp = Date.UTC(Number(depuis[1]), Number(depuis[2]) - 1, Number(depuis[3]));
  assert.equal(dateApp, NOUVEAUX_COMPTES_DEPUIS.getTime());
});

test('numéro : seuls les mobiles du Sénégal, rendus au format international', () => {
  for (const saisie of ['77 123 45 67', '771234567', '+221 77 123 45 67', '00221771234567', '221771234567', '77.123.45.67', '77-123-45-67']) {
    assert.equal(telephoneE164(saisie), '+221771234567', saisie);
  }
  assert.equal(telephoneE164('+221701234567'), '+221701234567');
  for (const refuse of ['', '12345', '+33612345678', '+221331234567', '+22177123456', '+2217712345678', '771234 56x', null, undefined, 771234567, {}]) {
    assert.equal(telephoneE164(refuse), null, String(refuse));
  }
});

test('prénom affiché : le prénom du profil, sinon le premier mot du nom, sans caractère dangereux', () => {
  assert.equal(prenomPour(profil({ prenom: 'Moussa', nom: 'Moussa Diop' })), 'Moussa');
  assert.equal(prenomPour(profil({ nom: '  Awa   Ndiaye ' })), 'Awa');
  assert.ok(!/[<>&"'`]/.test(prenomPour(profil({ nom: '<script>alert("1")</script> Fall' }))), 'balise ou guillemet conservé');
  assert.equal(prenomPour(profil({ nom: 'A'.repeat(100) })).length, 40);
  assert.equal(prenomPour(profil({})), '');
  assert.equal(prenomPour(profil({ nom: 42, prenom: '' })), '');
});

test('« Bienvenue chez SPRINT » : le titre est celui du client, le texte dépend du rôle et salue par le prénom', () => {
  const client = messageBienvenue('client', 'Awa');
  assert.equal(client.titre, 'Bienvenue chez SPRINT');
  assert.match(client.accroche, /^Bonjour Awa,/);
  assert.ok(client.points.length >= 3);
  assert.match(client.points.join(' '), /course/);
  const chauffeur = messageBienvenue('conducteur', 'Moussa');
  assert.equal(chauffeur.titre, 'Bienvenue chez SPRINT');
  assert.match(chauffeur.points.join(' '), /dossier/);
  assert.notEqual(client.notification, chauffeur.notification);
  assert.match(messageBienvenue('client', '').accroche, /^Bonjour,/, 'sans prénom, pas de « Bonjour , »');
});

test('mêmes mots dans l\'écran de l\'app et dans la notification et l\'e-mail du serveur', () => {
  const ecran = source('lib/features/auth/presentation/bienvenue_sprint_page.dart');
  for (const role of ['client', 'conducteur']) {
    const message = messageBienvenue(role, '');
    assert.ok(ecran.includes(`titre: '${message.titre}'`), `titre (${role})`);
    // L'accroche est « Bonjour <prénom>, <suite> » : la suite doit être la même des deux côtés.
    const suite = message.accroche.replace(/^Bonjour,? ?/, '');
    assert.ok(ecran.includes(suite), `accroche (${role}) : ${suite}`);
    for (const point of message.points) assert.ok(ecran.includes(point), `point (${role}) : ${point}`);
  }
});

test('e-mail de bienvenue : objet, texte et HTML ; rien d\'injectable dans le HTML', () => {
  const message = messageBienvenue('client', '<img src=x onerror=alert(1)>');
  const courriel = courrielBienvenue('awa@exemple.sn', message);
  assert.deepEqual(courriel.to, ['awa@exemple.sn']);
  assert.equal(courriel.replyTo, ADRESSE_SUPPORT);
  assert.equal(courriel.message.subject, 'Bienvenue chez SPRINT');
  assert.ok(courriel.message.text.includes('Bienvenue chez SPRINT'));
  assert.ok(courriel.message.html.includes('Bienvenue chez SPRINT'));
  assert.ok(!courriel.message.html.includes('<img'), 'balise injectée');
  assert.ok(courriel.message.html.includes('&lt;img'), 'le texte est échappé, pas supprimé');
  assert.ok(!/<script/i.test(courriel.message.html));
});

// --- Fermé : les fonctions ne font rien et ne touchent à aucune donnée ---------------------

const basDeDonnees = new Proxy({}, { get: () => { throw new Error('la base ne doit pas être touchée'); } }) as never;
const refuser: VerifierJetonTelephone = async () => { throw new Error('le jeton ne doit pas être lu'); };
const comptesInterdits: ComptesAuth = {
  lire: async () => { throw new Error('Firebase Auth ne doit pas être lu'); },
  supprimerSessionTelephone: async () => { throw new Error('rien à supprimer'); },
};

async function code(promesse: Promise<unknown>): Promise<string> {
  try {
    await promesse;
  } catch (e) {
    assert.ok(e instanceof HttpsError, String(e));
    return e.code;
  }
  return 'aucune erreur';
}

test('fermé : la validation du numéro est refusée avant toute lecture (jeton, base, Auth)', async () => {
  const demande = { jeton: 'x'.repeat(40) };
  assert.equal(await code(validerTelephone(basDeDonnees, refuser, comptesInterdits, 'awa', demande, new Date())), 'failed-precondition');
  assert.equal(await code(validerTelephone(basDeDonnees, refuser, comptesInterdits, undefined, demande, new Date(), 'obligatoire')), 'unauthenticated');
});

test('ouvert : une demande sans jeton valable est refusée avant toute lecture', async () => {
  for (const mauvaise of [undefined, null, {}, { jeton: 12 }, { jeton: 'court' }, { jeton: 'x'.repeat(5000) }, 'jeton']) {
    assert.equal(
      await code(validerTelephone(basDeDonnees, refuser, comptesInterdits, 'awa', mauvaise, new Date(), 'facultative')),
      'invalid-argument',
      JSON.stringify(mauvaise)?.slice(0, 30),
    );
  }
});

test('fermé : la bienvenue ne lit ni la base ni Firebase Auth et ne répond pas d\'erreur', async () => {
  assert.deepEqual(await declencherBienvenue(basDeDonnees, comptesInterdits, undefined, 'awa', new Date()), { envoye: false, raison: 'ferme' });
  assert.equal(await code(declencherBienvenue(basDeDonnees, comptesInterdits, undefined, undefined, new Date())), 'unauthenticated');
});

// --- Câblage dans index.ts -----------------------------------------------------------------

test('index.ts : les deux fonctions sont exportées, observées, et branchées sur les vrais accès Firebase', () => {
  const index = source('functions/src/index.ts');
  assert.match(index, /export const validerTelephone = onCall\(/);
  assert.match(index, /sansRetarder\(frequence\.observer\('validerTelephone'/);
  assert.match(index, /export const declencherBienvenue = onCall\(/);
  assert.match(index, /validerTelephoneCore\(getFirestore\(\), verifierJetonFirebase, new ComptesFirebase\(\)/);
  assert.match(index, /declencherBienvenueCore\(getFirestore\(\), new ComptesFirebase\(\), messagerie/);
  // Aucun secret nouveau : ni clé d'envoi d'e-mails ni mot de passe SMTP dans le code.
  assert.ok(!/smtp|apikey|api_key|password|secret/i.test(source('functions/src/inscription.ts').replace(/mot de passe/gi, '')), 'secret ou clé en clair');
});

test('le lot ne touche qu\'à trois collections (users, telephones_valides, mail) et à aucun champ de paiement ni de compte de test', () => {
  const inscription = source('functions/src/inscription.ts');
  const collections = [...inscription.matchAll(/db\.(?:doc|collection)\(\s*[`'"]([a-z_]+)/g)].map((m) => m[1]);
  assert.deepEqual([...new Set(collections)].sort(), ['mail', 'telephones_valides', 'users']);
  for (const champ of ['testeurOrangeMoney', 'argentDeTest', 'soldeFcfa', 'montantFcfa', 'statutCompte']) {
    assert.ok(!inscription.includes(champ), `${champ} ne doit pas apparaître dans inscription.ts`);
  }
});
