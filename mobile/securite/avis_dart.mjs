#!/usr/bin/env node
// Contrôle des avis de sécurité publiés pour les paquets Dart/Flutter
// verrouillés dans pubspec.lock (base d'avis de pub.dev, alimentée par
// GitHub Security Advisories / OSV).
//
//   node securite/avis_dart.mjs [pubspec.lock]
//
// Bloque (code 1) si une version verrouillée est touchée par un avis sans
// exception valable dans securite/exceptions.json (projet « dart »). Une base
// injoignable ne bloque pas le déploiement, mais le contrôle le dit.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { annoncerAvertissement, annoncerErreur, chargerExceptions, exceptionEchue, exceptionValable } from './commun.mjs';

const PROJET = 'dart';

/** Paquets hébergés sur pub.dev dans un pubspec.lock : [{ nom, version }]. */
export function lirePubspecLock(texte) {
  const paquets = [];
  let courant = null;
  let dansPaquets = false;
  for (const ligne of texte.split(/\r?\n/)) {
    if (/^\S/.test(ligne)) {
      dansPaquets = /^packages:\s*$/.test(ligne);
      courant = null;
      continue;
    }
    if (!dansPaquets) continue;
    const entete = /^ {2}([A-Za-z0-9_]+):\s*$/.exec(ligne);
    if (entete) {
      courant = { nom: entete[1], version: null, source: null, url: null };
      paquets.push(courant);
      continue;
    }
    if (!courant) continue;
    let m;
    if ((m = /^ {4}source:\s*(\S+)/.exec(ligne))) courant.source = m[1];
    else if ((m = /^ {4}version:\s*"?([^"\s]+)"?/.exec(ligne))) courant.version = m[1];
    else if ((m = /^ {6}url:\s*"?([^"\s]+)"?/.exec(ligne))) courant.url = m[1];
  }
  return paquets
    .filter((p) => p.source === 'hosted' && p.version && (p.url ?? 'https://pub.dev').startsWith('https://pub.dev'))
    .map(({ nom, version }) => ({ nom, version }));
}

/** Ordre des versions façon pub_semver (pré-version avant la version, métadonnées de build après). */
export function comparerVersions(a, b) {
  const lire = (v) => {
    const m = /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$/.exec(v);
    if (!m) return null;
    return { nombres: [Number(m[1]), Number(m[2]), Number(m[3])], pre: m[4]?.split('.') ?? null, build: m[5]?.split('.') ?? null };
  };
  const x = lire(a);
  const y = lire(b);
  if (!x || !y) return String(a).localeCompare(String(b));
  for (let i = 0; i < 3; i++) if (x.nombres[i] !== y.nombres[i]) return x.nombres[i] < y.nombres[i] ? -1 : 1;
  const comparerListes = (p, q, absentPlusGrand) => {
    if (!p && !q) return 0;
    if (!p) return absentPlusGrand ? 1 : -1;
    if (!q) return absentPlusGrand ? -1 : 1;
    for (let i = 0; i < Math.max(p.length, q.length); i++) {
      if (p[i] === undefined) return -1;
      if (q[i] === undefined) return 1;
      const pn = /^\d+$/.test(p[i]);
      const qn = /^\d+$/.test(q[i]);
      if (pn && qn) {
        if (Number(p[i]) !== Number(q[i])) return Number(p[i]) < Number(q[i]) ? -1 : 1;
      } else if (pn !== qn) {
        return pn ? -1 : 1;
      } else if (p[i] !== q[i]) {
        return p[i] < q[i] ? -1 : 1;
      }
    }
    return 0;
  };
  return comparerListes(x.pre, y.pre, true) || comparerListes(x.build, y.build, false);
}

/** La version est-elle touchée par cet avis (format OSV de pub.dev) ? */
export function versionTouchee(version, avis) {
  for (const a of avis.affected ?? []) {
    if ((a.versions ?? []).includes(version)) return true;
    for (const plage of a.ranges ?? []) {
      if (plage.type && plage.type !== 'ECOSYSTEM' && plage.type !== 'SEMVER') continue;
      const evenements = (plage.events ?? [])
        .map((e) => ({ ...e, borne: e.introduced ?? e.fixed ?? e.last_affected }))
        .filter((e) => typeof e.borne === 'string')
        .sort((e1, e2) => (e1.borne === '0' ? -1 : e2.borne === '0' ? 1 : comparerVersions(e1.borne, e2.borne)));
      let touchee = false;
      for (const e of evenements) {
        if (typeof e.introduced === 'string' && (e.introduced === '0' || comparerVersions(version, e.introduced) >= 0)) touchee = true;
        if (typeof e.fixed === 'string' && comparerVersions(version, e.fixed) >= 0) touchee = false;
        if (typeof e.last_affected === 'string' && comparerVersions(version, e.last_affected) > 0) touchee = false;
      }
      if (touchee) return true;
    }
  }
  return false;
}

async function avisDuPaquet(nom, fetcher) {
  let derniere = null;
  for (let essai = 0; essai < 3; essai++) {
    try {
      const reponse = await fetcher(`https://pub.dev/api/packages/${encodeURIComponent(nom)}/advisories`, {
        signal: AbortSignal.timeout(20000),
      });
      if (!reponse.ok) throw new Error(`HTTP ${reponse.status}`);
      const corps = await reponse.json();
      return Array.isArray(corps.advisories) ? corps.advisories : [];
    } catch (e) {
      derniere = e;
    }
  }
  throw derniere;
}

/**
 * Interroge la base d'avis pour chaque paquet et renvoie les avis qui
 * touchent la version verrouillée, plus les paquets restés sans réponse.
 */
export async function controler(paquets, { fetcher = fetch, exceptions = [], aujourdhui = new Date(), parallele = 8 } = {}) {
  const bloquants = [];
  const toleres = [];
  const echues = [];
  const injoignables = [];
  let suivant = 0;
  async function travailleur() {
    while (suivant < paquets.length) {
      const paquet = paquets[suivant++];
      let avis;
      try {
        avis = await avisDuPaquet(paquet.nom, fetcher);
      } catch {
        injoignables.push(paquet.nom);
        continue;
      }
      for (const a of avis) {
        if (a.withdrawn || !versionTouchee(paquet.version, a)) continue;
        const fiche = { id: a.id, paquet: paquet.nom, version: paquet.version, resume: a.summary ?? '' };
        if (exceptions.some((e) => exceptionValable(e, { avis: a.id, projet: PROJET }, aujourdhui))) toleres.push(fiche);
        else {
          if (exceptions.some((e) => exceptionEchue(e, { avis: a.id, projet: PROJET }, aujourdhui))) echues.push(fiche);
          bloquants.push(fiche);
        }
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(parallele, paquets.length) }, travailleur));
  return { controles: paquets.length, bloquants, toleres, echues, injoignables };
}

async function principal(argv) {
  const fichier = argv[0] ?? 'pubspec.lock';
  const paquets = lirePubspecLock(readFileSync(fichier, 'utf8'));
  if (paquets.length === 0) {
    console.error(`Aucun paquet hébergé trouvé dans ${fichier}.`);
    return 2;
  }
  const bilan = await controler(paquets, { exceptions: chargerExceptions() });
  console.log(
    `Avis Dart · ${bilan.controles} paquets contrôlés : ${bilan.bloquants.length} bloquant(s), ` +
      `${bilan.toleres.length} toléré(s), ${bilan.injoignables.length} sans réponse.`,
  );
  for (const a of bilan.toleres) console.log(`  toléré  ${a.id} ${a.paquet} ${a.version}`);
  for (const a of bilan.echues) {
    annoncerAvertissement('Exception échue', `${a.id} (${a.paquet}) : l'exception de securite/exceptions.json est échue, l'avis bloque de nouveau.`);
  }
  for (const a of bilan.bloquants) {
    console.log(`  BLOQUANT ${a.id} ${a.paquet} ${a.version} ${a.resume}`);
    annoncerErreur('Paquet Dart vulnérable', `${a.paquet} ${a.version} : ${a.id} ${a.resume}`);
  }
  if (bilan.injoignables.length > 0) {
    annoncerAvertissement(
      'Base d\'avis pub.dev incomplète',
      `${bilan.injoignables.length}/${bilan.controles} paquets sans réponse (${bilan.injoignables.slice(0, 5).join(', ')}…) : contrôle refait au prochain passage.`,
    );
  }
  return bilan.bloquants.length > 0 ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) principal(process.argv.slice(2)).then((code) => process.exit(code));
