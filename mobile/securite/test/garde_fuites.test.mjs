import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { clesAutorisees, masquer, scannerDiff, scannerDossier, scannerTexte } from '../garde_fuites.mjs';

const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'garde_fuites.mjs');

// Les faux secrets sont assemblés ici : aucun n'est écrit en entier dans ce dépôt public.
const faux = {
  'clé privée': '-----BEGIN ' + 'RSA PRIVATE KEY-----',
  'compte de service': '"private_key_id": "' + 'a1b2c3d4e5'.repeat(4) + '"',
  'jeton GitHub': 'ghp' + '_' + 'A'.repeat(36),
  'clé AWS': 'AKIA' + 'ABCDEFGHIJKLMNOP',
  'clé sk_live': 'sk' + '_live_' + 'x'.repeat(24),
  'jeton Slack': 'xoxb' + '-' + '1234567890-abcdef',
  'clé Wave': 'wave_sn_prod_' + 'Z'.repeat(24),
  'jeton JWT': 'eyJ' + 'a'.repeat(20) + '.eyJ' + 'b'.repeat(20) + '.' + 'c'.repeat(20),
  'adresse avec identifiants': 'postgres' + '://' + 'admin:' + 'motdepasse' + '@db.exemple.com/base',
  'clé Google': 'AIza' + 'S'.repeat(35),
};

const dossierTemporaire = () => mkdtempSync(path.join(tmpdir(), 'garde-'));

test('chaque famille de secret est détectée, et jamais affichée en entier', () => {
  for (const [nom, valeur] of Object.entries(faux)) {
    const trouvailles = scannerTexte(`const x = '${valeur}';`, { chemin: 'a.txt' });
    assert.ok(trouvailles.length >= 1, `${nom} non détecté`);
    assert.ok(!JSON.stringify(trouvailles).includes(valeur), `${nom} affiché en entier`);
  }
});

test('masquer : 4 caractères et la longueur, rien de plus', () => {
  assert.equal(masquer('abcdefghijkl'), 'abcd… (12 car.)');
  assert.ok(!masquer(faux['jeton GitHub']).includes(faux['jeton GitHub'].slice(8)));
});

test('du code ordinaire ne déclenche rien', () => {
  const code = [
    "final url = 'https://sprint-vtc.web.app/aide';",
    'const cle = String.fromEnvironment("GOOGLE_MAPS_WEB_KEY");',
    "const dev = 'postgresql://sprint:sprint@localhost:5432/sprint';",
    'sha256: "1a2b3c4d5e6f1a2b3c4d5e6f1a2b3c4d5e6f1a2b3c4d5e6f1a2b3c4d5e6f1a2b"',
    '// jeton : voir Secret Manager',
  ].join('\n');
  assert.deepEqual(scannerTexte(code, { chemin: 'mobile/lib/x.dart' }), []);
});

// Cas réel : le snapshot Dart de l'APK (libapp.so) range à la suite l'adresse de développement
// « http://10.0.2.2:3000 » (émulateur Android) et des noms Dart privés du type « _consumer@16069316 ».
// Lu comme du texte, cela ressemblait à une adresse « http » avec utilisateur, mot de passe et serveur.
// (Assemblé en morceaux : aucune adresse avec identifiants n'est écrite en entier dans ce dépôt public.)
const VOISINS_DU_SNAPSHOT = 'http://10.0.2.2:3000' + 'pausednull' + '¤' + '_consumer@16069316Datagram';

test('binaire : des chaînes voisines par hasard ne forment pas une adresse avec identifiants', () => {
  // Octet d'en-tête non imprimable entre les chaînes : jamais une adresse, même en texte.
  assert.deepEqual(scannerTexte(VOISINS_DU_SNAPSHOT, { chemin: 'lib/arm64-v8a/libapp.so', client: true }), []);
  assert.deepEqual(scannerTexte('http://10.0.2.2:3000' + '\x00pausednull\x01_consumer@16069316Datagram', { client: true }), []);

  // Même sans octet d'en-tête : dans un binaire, un serveur sans point n'est pas une adresse en ligne.
  const imprimable = 'http://10.0.2.2:3000' + 'pausednull_consumer@16069316Datagram';
  assert.equal(scannerTexte(imprimable, { client: true, binaire: false }).length, 1, 'en texte, le doute reste signalé');
  assert.deepEqual(scannerTexte(imprimable, { client: true, binaire: true }), []);
});

test('binaire : une vraie adresse avec identifiants reste trouvée', () => {
  const vraie = 'https://' + 'admin:' + 'motdepasse' + '@db.exemple.com/base';
  for (const binaire of [false, true]) {
    const trouvailles = scannerTexte(`\x00\x01${vraie}\x02`, { client: true, binaire });
    assert.equal(trouvailles.length, 1, `binaire=${binaire}`);
    assert.equal(trouvailles[0].motif, 'adresse de service avec identifiants');
    assert.ok(!JSON.stringify(trouvailles).includes('motdepasse'));
  }
});

test('APK : le snapshot Dart et ses voisinages binaires ne déclenchent plus de fausse alerte', () => {
  const apk = dossierTemporaire();
  try {
    mkdirSync(path.join(apk, 'lib/arm64-v8a'), { recursive: true });
    const so = Buffer.concat([
      Buffer.from([0x7f, 0x45, 0x4c, 0x46, 0x02, 0x01, 0x00, 0x00]),
      Buffer.from(VOISINS_DU_SNAPSHOT, 'latin1'),
      Buffer.from([0x20, 0x00, 0xa0, 0x0a]),
    ]);
    writeFileSync(path.join(apk, 'lib/arm64-v8a/libapp.so'), so);
    assert.equal(scannerDossier(apk, {}, '/inexistant', { binaire: true }).trouvailles.length, 0);

    const secret = 'https://' + 'admin:' + 'motdepasse' + '@db.exemple.com/base';
    writeFileSync(path.join(apk, 'lib/arm64-v8a/libflutter.so'), Buffer.concat([so, Buffer.from(secret, 'latin1')]));
    const bilan = scannerDossier(apk, {}, '/inexistant', { binaire: true });
    assert.equal(bilan.trouvailles.length, 1);
    assert.equal(bilan.trouvailles[0].chemin, path.join('lib/arm64-v8a', 'libflutter.so'));
  } finally {
    rmSync(apk, { recursive: true, force: true });
  }
});

test('clé Google : admise seulement si elle est connue comme publique', () => {
  const connue = faux['clé Google'];
  const autorisees = new Set([connue]);
  assert.deepEqual(scannerTexte(connue, { autorisees }), []);
  const inconnue = 'AIza' + 'T'.repeat(35);
  const trouvailles = scannerTexte(inconnue, { autorisees });
  assert.equal(trouvailles.length, 1);
  assert.equal(trouvailles[0].motif, 'clé API Google non autorisée');
});

test('noms des secrets du serveur : interdits dans le code client, permis côté serveur', () => {
  const dansApp = (texte, chemin) => scannerTexte(texte, { chemin }).length;
  assert.equal(dansApp('WAVE_API_KEY', 'mobile/lib/x.dart'), 1);
  assert.equal(dansApp('ORANGE_MONEY_CLIENT_SECRET', 'mobile/web/index.html'), 1);
  assert.equal(dansApp('FIREBASE_SERVICE_ACCOUNT', 'mobile/android/app/build.gradle'), 1);
  assert.equal(dansApp('GOOGLE_MAPS_API_KEY', 'mobile/lib/y.dart'), 1);
  assert.equal(dansApp('WAVE_API_KEY', 'mobile/functions/src/index.ts'), 0);
  assert.equal(dansApp('WAVE_API_KEY', '.github/workflows/flutter-web.yml'), 0);
  // Clés de carte restreintes : autres noms, présentes par conception dans l'app.
  assert.equal(dansApp('GOOGLE_MAPS_WEB_KEY GOOGLE_MAPS_ANDROID_KEY', 'mobile/lib/y.dart'), 0);
  // Site compilé et APK : tout est « client ».
  assert.equal(scannerTexte('WAVE_WEBHOOK_SECRET', { chemin: 'main.dart.js', client: true }).length, 1);
});

test('clés admises : firebase_options.dart et variables d\'environnement', () => {
  const racine = dossierTemporaire();
  try {
    mkdirSync(path.join(racine, 'mobile/lib'), { recursive: true });
    const firebase = 'AIza' + 'F'.repeat(35);
    writeFileSync(path.join(racine, 'mobile/lib/firebase_options.dart'), `apiKey: '${firebase}',\n`);
    const carte = 'AIza' + 'C'.repeat(35);
    const cles = clesAutorisees(racine, { GOOGLE_MAPS_WEB_KEY: carte, CLES_PUBLIQUES_AUTORISEES: ' autre , ' });
    assert.ok(cles.has(firebase));
    assert.ok(cles.has(carte));
    assert.ok(cles.has('autre'));
    assert.equal(clesAutorisees('/dossier/inexistant', {}).size, 0);
  } finally {
    rmSync(racine, { recursive: true, force: true });
  }
});

test('site compilé : un secret dans un fichier est trouvé, une clé de carte injectée à la compilation passe', () => {
  const site = dossierTemporaire();
  try {
    const carte = 'AIza' + 'M'.repeat(35);
    writeFileSync(path.join(site, 'main.dart.js'), `var k="${carte}";`);
    assert.equal(scannerDossier(site, { GOOGLE_MAPS_WEB_KEY: carte }, '/inexistant').trouvailles.length, 0);
    assert.equal(scannerDossier(site, {}, '/inexistant').trouvailles.length, 1);

    mkdirSync(path.join(site, 'assets'));
    writeFileSync(path.join(site, 'assets/config.json'), `{"cle":"${faux['jeton GitHub']}"}`);
    const bilan = scannerDossier(site, { GOOGLE_MAPS_WEB_KEY: carte }, '/inexistant');
    assert.equal(bilan.trouvailles.length, 1);
    assert.equal(bilan.trouvailles[0].chemin, path.join('assets', 'config.json'));
  } finally {
    rmSync(site, { recursive: true, force: true });
  }
});

test('commande : code 1 et rien d\'entier dans la sortie ; code 0 sur un dossier propre', () => {
  const site = dossierTemporaire();
  try {
    writeFileSync(path.join(site, 'index.html'), '<html>bonjour</html>');
    const propre = spawnSync('node', [SCRIPT, 'dossier', site], { encoding: 'utf8', cwd: site });
    assert.equal(propre.status, 2, 'hors dépôt git : erreur d\'usage, pas un faux « propre »');

    const depot = dossierTemporaire();
    try {
      spawnSync('git', ['init', '-q'], { cwd: depot });
      writeFileSync(path.join(depot, 'a.js'), 'rien');
      const sain = spawnSync('node', [SCRIPT, 'dossier', depot], { encoding: 'utf8', cwd: depot });
      assert.equal(sain.status, 0, sain.stdout + sain.stderr);

      const secret = faux['jeton GitHub'];
      writeFileSync(path.join(depot, 'b.js'), `const t = "${secret}";`);
      const fuite = spawnSync('node', [SCRIPT, 'dossier', depot], { encoding: 'utf8', cwd: depot });
      assert.equal(fuite.status, 1);
      assert.ok(fuite.stdout.includes('::error'), 'annotation GitHub attendue');
      assert.ok(!fuite.stdout.includes(secret), 'secret affiché en entier');
      assert.ok(!fuite.stdout.includes(secret.slice(10)), 'queue du secret affichée');
    } finally {
      rmSync(depot, { recursive: true, force: true });
    }
  } finally {
    rmSync(site, { recursive: true, force: true });
  }
});

test('diff : seules les lignes ajoutées comptent, avec leur numéro de ligne', () => {
  const depot = dossierTemporaire();
  const env = { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@t', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@t' };
  const git = (...args) => {
    const r = spawnSync('git', args, { cwd: depot, env, encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);
    return r.stdout.trim();
  };
  try {
    git('init', '-q');
    const ancien = faux['clé AWS']; // déjà présent avant : hors du périmètre du diff
    writeFileSync(path.join(depot, 'conf.txt'), `ligne 1\n${ancien}\nligne 3\n`);
    git('add', '.');
    git('commit', '-q', '-m', 'v1');
    const nouveau = faux['jeton GitHub'];
    writeFileSync(path.join(depot, 'conf.txt'), `ligne 1\n${ancien}\nligne 3\nnouvelle ligne\ntoken=${nouveau}\n`);
    git('add', '.');
    git('commit', '-q', '-m', 'v2');

    const bilan = scannerDiff(depot, 'HEAD~1', 'HEAD', {});
    assert.equal(bilan.ajoutees, 2);
    assert.equal(bilan.trouvailles.length, 1);
    assert.equal(bilan.trouvailles[0].chemin, 'conf.txt');
    assert.equal(bilan.trouvailles[0].ligne, 5);
    assert.equal(bilan.trouvailles[0].motif, 'jeton GitHub');
  } finally {
    rmSync(depot, { recursive: true, force: true });
  }
});
