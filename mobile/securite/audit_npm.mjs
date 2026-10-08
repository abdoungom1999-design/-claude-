#!/usr/bin/env node
// Contrôle des vulnérabilités connues (npm audit) d'un projet Node du dépôt.
//
//   node securite/audit_npm.mjs <dossier> [--prod] [--seuil moderate|high|critical]
//
// Bloque (code 1) dès qu'un avis de gravité >= seuil touche le projet sans
// exception valable dans securite/exceptions.json. Si l'audit lui-même ne
// peut pas tourner (registre npm injoignable), le contrôle ne bloque pas le
// déploiement mais le dit clairement : il sera refait au prochain passage.
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  annoncerAvertissement,
  annoncerErreur,
  chargerExceptions,
  exceptionEchue,
  exceptionValable,
} from './commun.mjs';

const GRAVITES = ['info', 'low', 'moderate', 'high', 'critical'];
const rang = (gravite) => GRAVITES.indexOf(gravite);

/** Identifiant stable d'un avis (GHSA-… dans l'adresse, à défaut son numéro). */
function identifiantAvis(via) {
  const fin = typeof via.url === 'string' ? via.url.split('/').pop() : '';
  return fin || String(via.source ?? 'inconnu');
}

/**
 * Lit le rapport `npm audit --json` (version 2). Seuls les avis eux-mêmes
 * comptent : un paquet « vulnérable » parce qu'il dépend d'un autre n'est
 * que la conséquence d'un avis déjà listé.
 */
export function analyserRapport(rapport, { seuil = 'high', exceptions = [], projet = '', aujourdhui = new Date() } = {}) {
  const avis = new Map();
  for (const [paquet, v] of Object.entries(rapport.vulnerabilities ?? {})) {
    for (const via of v.via ?? []) {
      if (typeof via !== 'object' || via === null) continue;
      const id = identifiantAvis(via);
      if (!avis.has(id)) {
        avis.set(id, { id, paquet: via.name ?? paquet, gravite: via.severity, titre: via.title ?? '', plage: via.range ?? '' });
      }
    }
  }

  const bloquants = [];
  const toleres = [];
  const echues = [];
  let sousSeuil = 0;
  for (const a of avis.values()) {
    if (rang(a.gravite) < rang(seuil)) {
      sousSeuil++;
      continue;
    }
    if (exceptions.some((e) => exceptionValable(e, { avis: a.id, projet }, aujourdhui))) {
      toleres.push(a);
      continue;
    }
    if (exceptions.some((e) => exceptionEchue(e, { avis: a.id, projet }, aujourdhui))) echues.push(a);
    bloquants.push(a);
  }
  return { total: avis.size, sousSeuil, bloquants, toleres, echues };
}

function lancerAudit(dossier, prod) {
  const resultat = spawnSync('npm', ['audit', '--json', ...(prod ? ['--omit=dev'] : [])], {
    cwd: dossier,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  try {
    const rapport = JSON.parse(resultat.stdout);
    if (rapport.error) return { indisponible: String(rapport.error.summary ?? rapport.error.code ?? 'erreur npm') };
    return { rapport };
  } catch {
    return { indisponible: (resultat.stderr || resultat.error?.message || 'réponse illisible').slice(0, 300) };
  }
}

function principal(argv) {
  const dossier = argv[0];
  if (!dossier) {
    console.error('Usage : audit_npm.mjs <dossier> [--prod] [--seuil moderate|high|critical]');
    return 2;
  }
  const prod = argv.includes('--prod');
  const seuil = argv.includes('--seuil') ? argv[argv.indexOf('--seuil') + 1] : 'high';
  if (rang(seuil) < 0) {
    console.error(`Seuil inconnu : ${seuil}`);
    return 2;
  }
  const projet = path.basename(path.resolve(dossier));
  const etiquette = `${projet}${prod ? ' (production)' : ''}, seuil ${seuil}`;

  const { rapport, indisponible } = lancerAudit(dossier, prod);
  if (!rapport) {
    annoncerAvertissement('Audit des dépendances indisponible', `${etiquette} : ${indisponible}. Contrôle refait au prochain passage.`);
    return 0;
  }
  const bilan = analyserRapport(rapport, { seuil, exceptions: chargerExceptions(), projet });
  console.log(
    `Audit npm · ${etiquette} : ${bilan.total} avis, ${bilan.bloquants.length} bloquant(s), ` +
      `${bilan.toleres.length} toléré(s), ${bilan.sousSeuil} sous le seuil.`,
  );
  for (const a of bilan.toleres) console.log(`  toléré  ${a.id} ${a.paquet} (${a.gravite})`);
  for (const a of bilan.echues) {
    annoncerAvertissement('Exception échue', `${a.id} (${a.paquet}) : l'exception de securite/exceptions.json est échue, l'avis bloque de nouveau.`);
  }
  for (const a of bilan.bloquants) {
    console.log(`  BLOQUANT ${a.id} ${a.paquet} ${a.plage} (${a.gravite}) ${a.titre}`);
    annoncerErreur('Dépendance vulnérable', `${projet} : ${a.paquet} ${a.plage} (${a.gravite}) ${a.id} ${a.titre}`);
  }
  return bilan.bloquants.length > 0 ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exit(principal(process.argv.slice(2)));
