// Contrôle du refus des clés Google (tool/verifier_refus_cle_google.sh) : le
// script est rejoué avec un faux `curl` qui renvoie la réponse voulue, sans
// jamais joindre Google ni utiliser une vraie clé.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const SCRIPT = new URL('../../tool/verifier_refus_cle_google.sh', import.meta.url).pathname;
const CLE = 'CLE_FICTIVE_POUR_LE_TEST_0123456789';

/** Joue le script avec un faux curl : `code` est le code HTTP rendu ("" = curl en échec). */
function jouer(args, { code, cle = CLE }) {
  const dossier = mkdtempSync(join(tmpdir(), 'refus-cle-'));
  const appels = join(dossier, 'appels.txt');
  writeFileSync(join(dossier, 'curl'), `#!/usr/bin/env bash
printf '%s\\n' "$*" >> '${appels}'
out=""
while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then out=$2; fi; shift; done
[ -n "$out" ] && echo '{"error":{"message":"réponse de Google (ne doit jamais être affichée)"}}' > "$out"
[ -n "$STUB_CODE" ] || exit 7
printf '%s' "$STUB_CODE"
`);
  chmodSync(join(dossier, 'curl'), 0o755);
  const resultat = spawnSync('bash', [SCRIPT, ...args], {
    env: { PATH: `${dossier}:${process.env.PATH}`, STUB_CODE: code, RUNNER_TEMP: dossier, ...(cle === null ? {} : { CLE: cle }) },
    encoding: 'utf8',
  });
  let appelsFaits = '';
  try { appelsFaits = readFileSync(appels, 'utf8'); } catch { /* aucun appel */ }
  return { ...resultat, sortie: resultat.stdout + resultat.stderr, appelsFaits };
}

test('clé web depuis un faux site : refus de Google = simple ligne, aucun avertissement', () => {
  const r = jouer(['appelant', 'Clé web', 'Referer: https://exemple.invalid/'], { code: '403' });
  assert.equal(r.status, 0);
  assert.match(r.sortie, /Clé web : clé refusée depuis un appelant inconnu \(HTTP 403\), comme prévu\./);
  assert.doesNotMatch(r.sortie, /::warning/);
  assert.match(r.appelsFaits, /tile\.googleapis\.com\/v1\/createSession/);
  assert.match(r.appelsFaits, /Referer: https:\/\/exemple\.invalid\//);
});

test('clé acceptée depuis un faux site : avertissement dans le résumé, sans bloquer', () => {
  const r = jouer(['appelant', 'Clé Android', 'X-Android-Package: invalide.exemple'], { code: '200' });
  assert.equal(r.status, 0, 'le contrôle ne bloque jamais le déploiement');
  assert.match(r.sortie, /::warning title=Clé Android::Clé acceptée par Google depuis un appelant inconnu/);
  assert.match(r.sortie, /console Google Cloud/);
});

test('autre API avec le vrai appelant : refus attendu, ou avertissement si la clé est acceptée', () => {
  const refus = jouer(['api', 'Clé web', 'Referer: https://sprint-vtc.web.app/'], { code: '403' });
  assert.match(refus.sortie, /clé refusée pour une API qui n'est pas la carte \(HTTP 403\), comme prévu\./);
  assert.doesNotMatch(refus.sortie, /::warning/);
  assert.match(refus.appelsFaits, /places\.googleapis\.com\/v1\/places:autocomplete/);
  assert.match(refus.appelsFaits, /Referer: https:\/\/sprint-vtc\.web\.app\//);

  const accepte = jouer(['api', 'Clé web', 'Referer: https://sprint-vtc.web.app/'], { code: '200' });
  assert.equal(accepte.status, 0);
  assert.match(accepte.sortie, /::warning title=Clé web::Clé acceptée par Google pour une API qui n'est pas la carte/);
});

test('Google injoignable ou réponse inattendue : contrôle non concluant, sans avertissement ni blocage', () => {
  for (const code of ['', '000', '500', '429']) {
    const r = jouer(['appelant', 'Clé web', 'Referer: https://exemple.invalid/'], { code });
    assert.equal(r.status, 0);
    assert.match(r.sortie, /contrôle non concluant/, `code « ${code} »`);
    assert.doesNotMatch(r.sortie, /::warning/, `code « ${code} »`);
  }
});

test('jamais la clé ni la réponse de Google dans le journal (public)', () => {
  for (const code of ['200', '403', '500', '']) {
    for (const mode of ['appelant', 'api']) {
      const r = jouer([mode, 'Clé web', 'Referer: https://exemple.invalid/'], { code });
      assert.doesNotMatch(r.sortie, new RegExp(CLE), `${mode} ${code}`);
      assert.doesNotMatch(r.sortie, /réponse de Google/, `${mode} ${code}`);
    }
  }
});

test('sans clé ou avec un mode inconnu : rien n\'est envoyé à Google, aucun blocage', () => {
  const sansCle = jouer(['appelant', 'Clé web'], { code: '200', cle: null });
  assert.equal(sansCle.status, 0);
  assert.match(sansCle.sortie, /pas de clé fournie, contrôle ignoré/);
  assert.equal(sansCle.appelsFaits, '');

  const inconnu = jouer(['n_importe_quoi', 'Clé web'], { code: '200' });
  assert.equal(inconnu.status, 0);
  assert.match(inconnu.sortie, /::warning title=Clé web::Contrôle mal appelé/);
  assert.equal(inconnu.appelsFaits, '');
});
