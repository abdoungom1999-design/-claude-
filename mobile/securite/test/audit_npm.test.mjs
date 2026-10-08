import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { analyserRapport } from '../audit_npm.mjs';
import { exceptionEchue, exceptionValable } from '../commun.mjs';

const aujourdhui = new Date('2026-10-08T12:00:00Z');

const avis = (ghsa, gravite, nom, plage = '<1.0.0') => ({
  source: Number(ghsa.replace(/\D/g, '').slice(0, 6)),
  name: nom,
  title: `faille de ${nom}`,
  url: `https://github.com/advisories/${ghsa}`,
  severity: gravite,
  range: plage,
});

// Forme de `npm audit --json` (version 2) : des avis, et des paquets « vulnérables par ricochet ».
const rapport = {
  auditReportVersion: 2,
  vulnerabilities: {
    uuid: { name: 'uuid', severity: 'moderate', via: [avis('GHSA-aaaa-1111-aaaa', 'moderate', 'uuid')] },
    gaxios: { name: 'gaxios', severity: 'moderate', via: ['uuid'] },
    tar: { name: 'tar', severity: 'critical', via: [avis('GHSA-bbbb-2222-bbbb', 'critical', 'tar'), avis('GHSA-cccc-3333-cccc', 'high', 'tar')] },
    'firebase-tools': { name: 'firebase-tools', severity: 'critical', via: ['tar', 'basic-ftp'] },
    'basic-ftp': { name: 'basic-ftp', severity: 'high', via: [avis('GHSA-dddd-4444-dddd', 'high', 'basic-ftp')] },
  },
};

const exception = (extra = {}) => ({
  avis: 'GHSA-dddd-4444-dddd', projet: 'firestore_rules_test', raison: 'Outil de test jamais déployé, entrée non contrôlée.', jusqu_au: '2026-12-31', ...extra,
});

test('les avis comptent, pas les paquets vulnérables par ricochet', () => {
  const bilan = analyserRapport(rapport, { seuil: 'moderate', aujourdhui });
  assert.equal(bilan.total, 4);
  assert.deepEqual(bilan.bloquants.map((a) => a.id).sort(), ['GHSA-aaaa-1111-aaaa', 'GHSA-bbbb-2222-bbbb', 'GHSA-cccc-3333-cccc', 'GHSA-dddd-4444-dddd']);
});

test('le seuil sépare ce qui bloque de ce qui est seulement signalé', () => {
  const haut = analyserRapport(rapport, { seuil: 'high', aujourdhui });
  assert.deepEqual(haut.bloquants.map((a) => a.id).sort(), ['GHSA-bbbb-2222-bbbb', 'GHSA-cccc-3333-cccc', 'GHSA-dddd-4444-dddd']);
  assert.equal(haut.sousSeuil, 1);

  const critique = analyserRapport(rapport, { seuil: 'critical', aujourdhui });
  assert.deepEqual(critique.bloquants.map((a) => a.id), ['GHSA-bbbb-2222-bbbb']);
  assert.equal(critique.sousSeuil, 3);

  assert.equal(analyserRapport({ auditReportVersion: 2, vulnerabilities: {} }, { aujourdhui }).bloquants.length, 0);
});

test('exception valable : l\'avis est toléré, avec le projet visé', () => {
  const bilan = analyserRapport(rapport, { seuil: 'high', exceptions: [exception()], projet: 'firestore_rules_test', aujourdhui });
  assert.deepEqual(bilan.toleres.map((a) => a.id), ['GHSA-dddd-4444-dddd']);
  assert.ok(!bilan.bloquants.some((a) => a.id === 'GHSA-dddd-4444-dddd'));
});

test('exception échue, sans vrai motif, ou pour un autre projet : l\'avis bloque', () => {
  const essai = (exc, projet = 'firestore_rules_test') => analyserRapport(rapport, { seuil: 'high', exceptions: [exc], projet, aujourdhui });
  const bloque = (b) => b.bloquants.some((a) => a.id === 'GHSA-dddd-4444-dddd');

  const echue = essai(exception({ jusqu_au: '2026-10-07' }));
  assert.ok(bloque(echue));
  assert.ok(echue.echues.some((a) => a.id === 'GHSA-dddd-4444-dddd'));

  assert.ok(bloque(essai(exception({ raison: 'ok' }))));
  assert.ok(bloque(essai(exception({ jusqu_au: 'bientôt' }))));
  assert.ok(bloque(essai(exception(), 'functions')));
  assert.ok(!bloque(essai(exception({ projet: '*' }), 'functions')));
});

test('dernier jour d\'une exception : encore valable toute la journée', () => {
  const e = exception({ jusqu_au: '2026-10-08' });
  assert.equal(exceptionValable(e, { avis: e.avis, projet: 'firestore_rules_test' }, new Date('2026-10-08T23:00:00Z')), true);
  assert.equal(exceptionValable(e, { avis: e.avis, projet: 'firestore_rules_test' }, new Date('2026-10-09T00:00:01Z')), false);
  assert.equal(exceptionEchue(e, { avis: e.avis, projet: 'firestore_rules_test' }, new Date('2026-10-09T00:00:01Z')), true);
});

test('securite/exceptions.json : JSON valide, chaque exception motivée et datée', () => {
  const fichier = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'exceptions.json');
  const contenu = JSON.parse(readFileSync(fichier, 'utf8'));
  assert.ok(Array.isArray(contenu.avis));
  for (const e of contenu.avis) {
    assert.match(e.avis, /^GHSA-/, 'identifiant GHSA attendu');
    assert.ok(typeof e.raison === 'string' && e.raison.trim().length >= 10, `motif manquant pour ${e.avis}`);
    assert.match(e.jusqu_au, /^\d{4}-\d{2}-\d{2}$/, `date de fin manquante pour ${e.avis}`);
  }
});
