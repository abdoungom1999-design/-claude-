import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { POURCENTAGE_COMMISSION_HISTORIQUE } from '../src/admin';

/** Fichier du projet (l'app Flutter, les règles Firestore), lu depuis functions/lib/test. */
const lire = (...chemin: string[]): string => readFileSync(resolve(__dirname, '..', '..', '..', ...chemin), 'utf8');

const SOURCE_APP = lire('lib', 'features', 'courses', 'data', 'course_service.dart');
const REGLES = lire('firestore.rules');

/** Premier nombre capturé par [motif] dans [source] ; le test échoue si le texte a changé de forme. */
function nombre(source: string, motif: RegExp, quoi: string): number {
  const trouve = source.match(motif);
  assert.ok(trouve, `${quoi} introuvable : le texte a-t-il changé de forme ?`);
  return Number(trouve[1]);
}

test('commission : le taux de l\'app (Commission.pourcentage) est celui que les règles Firestore font respecter : 10 %', () => {
  const app = nombre(SOURCE_APP, /static const pourcentage = (\d+);/, 'Commission.pourcentage');
  const regles = nombre(
    REGLES,
    /request\.resource\.data\.commissionFcfa == math\.floor\(resource\.data\.prixFcfa \* (\d+) \/ 100\)/,
    'la formule de la commission dans firestore.rules',
  );
  assert.equal(app, 10, 'décision du client du 13 octobre 2026');
  assert.equal(regles, app, 'si l\'app et les règles diffèrent, plus aucune course ne peut se terminer');
});

test('commission : l\'ancien taux de 15 % est le même dans l\'app (Commission.historique) et sur le serveur', () => {
  const app = nombre(SOURCE_APP, /static const pourcentageHistorique = (\d+);/, 'Commission.pourcentageHistorique');
  assert.equal(app, 15);
  assert.equal(POURCENTAGE_COMMISSION_HISTORIQUE, app);
});

test('commission : le serveur ne connaît pas le taux du jour, il lit la commission figée sur la course', () => {
  const serveur = readFileSync(resolve(__dirname, '..', '..', 'src', 'admin.ts'), 'utf8');
  assert.ok(!/POURCENTAGE_COMMISSION\b/.test(serveur), 'un taux « du jour » ne doit pas revenir côté serveur');
  assert.match(serveur, /course\.get\('commissionFcfa'\)/);
});

test('commission : même arrondi à l\'inférieur dans l\'app et les règles', () => {
  assert.match(SOURCE_APP, /static int de\(int prixFcfa\) => \(prixFcfa \* pourcentage\) ~\/ 100;/);
  assert.match(REGLES, /math\.floor\(resource\.data\.prixFcfa \* \d+ \/ 100\)/);
});
