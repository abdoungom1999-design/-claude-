import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { DOSSIER_SECURITE } from '../commun.mjs';

// Les flux de la CI sont à la racine du dépôt, au-dessus de mobile/.
const DOSSIER_FLUX = path.resolve(DOSSIER_SECURITE, '..', '..', '.github', 'workflows');
const MACHINE = 'ubuntu-24.04';

const lister = () => readdirSync(DOSSIER_FLUX).filter((nom) => nom.endsWith('.yml')).sort();
const lire = (nom) => readFileSync(path.join(DOSSIER_FLUX, nom), 'utf8');

/** Texte du job `nom` : de sa ligne « nom: » (2 espaces) jusqu'au job suivant, ou la fin du fichier. */
function job(texte, nom) {
  const lignes = texte.split('\n');
  const debut = lignes.findIndex((ligne) => ligne === `  ${nom}:`);
  assert.ok(debut >= 0, `job « ${nom} » introuvable`);
  const fin = lignes.findIndex((ligne, i) => i > debut && /^ {2}[A-Za-z0-9_-]+:\s*$/.test(ligne));
  return lignes.slice(debut, fin < 0 ? undefined : fin).join('\n');
}

/** Jobs listés dans `needs: [a, b]` d'un job. */
function besoins(texteJob) {
  const trouve = texteJob.match(/^ {4}needs: \[([^\]]*)\]\s*$/m);
  assert.ok(trouve, 'ligne « needs: [...] » introuvable');
  return trouve[1].split(',').map((nom) => nom.trim());
}

test('la CI existe où on la cherche (sinon ces contrôles ne vérifieraient rien)', () => {
  assert.ok(existsSync(DOSSIER_FLUX), `${DOSSIER_FLUX} introuvable`);
  assert.deepEqual(lister(), ['essai-android.yml', 'flutter-web.yml', 'restauration-essai.yml', 'sauvegardes.yml']);
});

test('machines figées : chaque job de chaque flux tourne sur ubuntu-24.04, jamais sur ubuntu-latest (décision du client, 14 octobre 2026)', () => {
  for (const nom of lister()) {
    const machines = [...lire(nom).matchAll(/^\s*runs-on:\s*(.*?)\s*$/gm)].map((m) => m[1]);
    assert.ok(machines.length > 0, `${nom} : aucun « runs-on » trouvé`);
    for (const machine of machines) {
      assert.equal(machine, MACHINE, `${nom} : « ${machine} » au lieu de « ${MACHINE} ». GitHub fait passer ubuntu-latest à Ubuntu 26 le 19 octobre 2026 : changer de système demande l'accord du client et un essai sans publication`);
    }
  }
});

test('essai sans publication : l\'option existe, firebase est sauté, et hebergement et deploy ne peuvent pas partir sans lui', () => {
  const principal = lire('flutter-web.yml');
  assert.match(principal, /^ {6}essai:\s*$/m, 'l\'option « essai » du lancement à la main est absente');

  // firebase (fonctions, règles) est sauté quand l'essai est coché.
  assert.match(job(principal, 'firebase'), /^ {4}if: \$\{\{[^\n]*inputs\.essai[^\n]*\}\}\s*$/m);

  // hebergement (site et APK en ligne) exige que firebase ait réussi, donc il est sauté avec lui ;
  // deploy (GitHub Pages) exige hebergement.
  const hebergement = job(principal, 'hebergement');
  assert.ok(besoins(hebergement).includes('firebase'));
  assert.match(hebergement, /^ {4}if: [^\n]*needs\.firebase\.result == 'success'/m);
  assert.deepEqual(besoins(job(principal, 'deploy')), ['hebergement']);
});

test('essai sans publication : l\'APK est quand même compilé, mais seulement après build et backend', () => {
  const android = job(lire('flutter-web.yml'), 'android');
  assert.deepEqual(besoins(android).sort(), ['backend', 'build', 'firebase']);
  const condition = android.match(/^ {4}if: (.*)$/m)?.[1] ?? '';
  assert.match(condition, /needs\.build\.result == 'success'/);
  assert.match(condition, /needs\.backend\.result == 'success'/);
  assert.match(condition, /needs\.firebase\.result == 'success'/, 'en lancement normal, android attend le déploiement du backend');
  assert.match(condition, /inputs\.essai/, 'seul l\'essai peut se passer du déploiement du backend');
});
