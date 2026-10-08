#!/usr/bin/env node
// Contrôles des outils de design externes (règle des zones : securite/ZONES_DESIGN.md,
// protections 3 et 4, fixées par le client).
//
//   node securite/outils_design.mjs diff <base> <tete>       fichiers d'un lot classés par zone (liste à joindre au compte rendu)
//   node securite/outils_design.mjs commits <base> <tete>    chaque commit déclaré « Lot-Design: oui » doit rester en zone autorisée
//   node securite/outils_design.mjs integrite                .claude/ : texte seul, conforme à securite/outils_externes.json
//
// Bloque (code 1) dès qu'un fichier sort de la zone autorisée, qu'une ligne
// nouvelle touche au serveur, à la base ou aux moyens de paiement, ou qu'un
// outil installé contient autre chose que du texte attendu. La zone autorisée
// est une LISTE BLANCHE : ce qui n'est écrit nulle part est refusé aussi.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, lstatSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { annoncerAvertissement, annoncerErreur, DOSSIER_SECURITE } from './commun.mjs';

/** Zone interdite : jamais touchée par un lot de design (ZONES_DESIGN.md). */
export const INTERDITES = [
  { regex: /^mobile\/functions\//, raison: 'serveur : Cloud Functions, paiements, webhooks Wave et Orange Money' },
  { regex: /^mobile\/(?:firestore\.rules|storage\.rules)$/, raison: 'règles de sécurité de la base et du stockage' },
  { regex: /^mobile\/firestore_rules_test\//, raison: 'tests des règles de sécurité' },
  { regex: /^mobile\/(?:firebase\.json|\.firebaserc|hebergement\/)/, raison: 'hébergement et en-têtes de sécurité' },
  { regex: /^\.github\//, raison: 'chaîne de publication (CI, déploiement)' },
  { regex: /^mobile\/securite\//, raison: 'contrôles de sécurité eux-mêmes' },
  { regex: /^\.claude\//, raison: 'outils externes eux-mêmes (installés et contrôlés à part)' },
  { regex: /(?:^|\/)\.mcp\.json$/, raison: 'serveur MCP (code exécuté par l’agent)' },
  { regex: /^mobile\/lib\/(?:.*\/)?data\//, raison: 'accès aux données et au serveur' },
  { regex: /^mobile\/lib\/core\/(?:firebase|network)\//, raison: 'accès au serveur et à l’authentification' },
  { regex: /^mobile\/lib\/firebase_options\.dart$/, raison: 'configuration Firebase' },
  { regex: /^mobile\/pubspec\.(?:yaml|lock)$/, raison: 'dépendances : une nouvelle dépendance passe par un contrôle de sécurité et par le client' },
  { regex: /^mobile\/web\/firebase-messaging-sw\.js$/, raison: 'notifications push (service worker)' },
  { regex: /^mobile\/test\/palette_bleu_orange_test\.dart$/, raison: 'garde-fou de la charte du client (modifiable sur son ordre seulement)' },
  { regex: /(?:^|\/)\.env(?:\.|$)/, raison: 'fichier de secrets' },
  { regex: /\.(?:pem|key|p12|pfx|jks|keystore)$/i, raison: 'clé ou certificat' },
  { regex: /(?:^|\/)(?:google-services\.json|GoogleService-Info\.plist|key\.properties)$/, raison: 'clés et configuration Firebase ou Android' },
  { regex: /service[-_]?account/i, raison: 'compte de service' },
];

/** Zone autorisée : l'apparence de l'app Flutter. `restreint` : contrôle de lignes renforcé. */
export const AUTORISEES = [
  { regex: /^mobile\/lib\/features\/[^/]+\/presentation\//, raison: 'écran (couche presentation)' },
  { regex: /^mobile\/lib\/core\/widgets\//, raison: 'widget partagé' },
  { regex: /^mobile\/lib\/core\/theme\//, raison: 'thème et palette' },
  { regex: /^mobile\/assets\//, raison: 'ressource visuelle' },
  { regex: /^mobile\/web\/(?:icons\/|splash\/|favicon\.png$)/, raison: 'icône ou écran de démarrage du site' },
  { regex: /^mobile\/web\/index\.html$/, raison: 'écran de démarrage du site (style seulement)', restreint: 'index' },
  { regex: /^mobile\/android\/app\/src\/main\/res\/(?:mipmap|drawable)[^/]*\//, raison: 'icône Android' },
  { regex: /^mobile\/test\/[^/]+_test\.dart$/, raison: 'test d’interface', test: true },
];

/** Écrans de paiement, de recharge et de connexion : habillage seulement, logique figée. */
const CAS_LIMITES = /(?:payment|paiement|portefeuille|wallet|recharge|\/auth\/|auth_scaffold|mot_de_passe)/i;

export const normaliser = (chemin) => String(chemin).replace(/\\/g, '/').replace(/^\.\//, '');

/** Zone d'un fichier (chemin relatif à la racine du dépôt). */
export function classer(cheminBrut) {
  const chemin = normaliser(cheminBrut);
  if (chemin.startsWith('/') || chemin.includes('\0') || chemin.split('/').includes('..')) {
    return { zone: 'interdite', raison: 'chemin suspect' };
  }
  for (const r of INTERDITES) {
    if (r.regex.test(chemin)) return { zone: 'interdite', raison: r.raison };
  }
  for (const r of AUTORISEES) {
    if (r.regex.test(chemin)) {
      return { zone: 'autorisee', raison: r.raison, limite: CAS_LIMITES.test(chemin), restreint: r.restreint, test: Boolean(r.test) };
    }
  }
  return {
    zone: 'hors_zone',
    raison: 'ni autorisé ni interdit explicitement : à faire valider par le client avant de l’ajouter à la zone',
  };
}

/** Une ligne NOUVELLE de code ne doit pas toucher au serveur, à la base ni aux secrets. */
export const MOTIFS_SERVEUR = [
  { nom: 'appel d’une Cloud Function', regex: /\bhttpsCallable\b|\bFirebaseFunctions\b|package:cloud_functions\// },
  { nom: 'accès à la base Firestore', regex: /\bFirebaseFirestore\b|package:cloud_firestore\// },
  { nom: 'authentification Firebase', regex: /\bFirebaseAuth\b|package:firebase_auth\// },
  { nom: 'stockage ou messagerie Firebase', regex: /\bFirebaseStorage\b|package:firebase_(?:storage|messaging|core)\// },
  { nom: 'requête réseau', regex: /package:(?:http|dio)\/|\bHttpClient\b|\bWebSocket(?:Channel)?\b|\bUri\.parse\(\s*['"]https?:/ },
  { nom: 'stockage de secrets', regex: /flutter_secure_storage|\bSecureStorage\b/ },
  { nom: 'valeur injectée à la compilation (clés)', regex: /\b(?:String|bool|int)\.fromEnvironment\b/ },
];

/** Identifiants figés : un lot de design ne les ajoute ni ne les retire. */
export const MOTIFS_FIGES = [
  { nom: 'liste des moyens de paiement ouverts (moyensMobileMoneyDisponibles)', regex: /\bmoyensMobileMoneyDisponibles\b/ },
  { nom: 'Orange Money (fermé par décision du client)', regex: /\bPaymentMethod\.orangeMoney\b|\borangeMoney\b|\bORANGE_MONEY\b/ },
];

/** web/index.html : du style, pas de script ni de requête. */
export const MOTIFS_INDEX = [
  { nom: 'script ou requête dans index.html', regex: /<script|\bfetch\s*\(|XMLHttpRequest|serviceWorker|\beval\s*\(|\bimport\s*\(|javascript:|\bon[a-z]+\s*=/i },
  { nom: 'adresse externe dans index.html', regex: /https?:\/\//i },
];

/** Multi-ensemble de lignes (texte nettoyé) : un déplacement de code n'est pas du code nouveau. */
function compter(lignes) {
  const m = new Map();
  for (const l of lignes) m.set(l.texte, (m.get(l.texte) ?? 0) + 1);
  return m;
}

function sansEquivalent(lignes, autres) {
  const restantes = compter(autres);
  const nouvelles = [];
  for (const l of lignes) {
    const n = restantes.get(l.texte) ?? 0;
    if (n > 0) restantes.set(l.texte, n - 1);
    else nouvelles.push(l);
  }
  return nouvelles;
}

/**
 * Lignes ajoutées et retirées d'un diff unifié (-U0). Une ligne ajoutée
 * ou retirée à l'identique ailleurs dans le même diff (déplacement,
 * réindentation) ne compte pas : seul le code NOUVEAU ou DISPARU est jugé.
 */
export function lignesDuDiff(diff) {
  const ajoutees = [];
  const retirees = [];
  let avant = '';
  let apres = '';
  let ligne = 0;
  for (const brute of diff.split('\n')) {
    let m;
    if ((m = /^--- (?:a\/(.*)|\/dev\/null)$/.exec(brute))) {
      avant = m[1] ?? '';
    } else if ((m = /^\+\+\+ (?:b\/(.*)|\/dev\/null)$/.exec(brute))) {
      apres = m[1] ?? '';
    } else if ((m = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(brute))) {
      ligne = Number(m[1]);
    } else if (brute.startsWith('+')) {
      ajoutees.push({ chemin: apres, texte: brute.slice(1).trim(), ligne });
      ligne++;
    } else if (brute.startsWith('-')) {
      retirees.push({ chemin: avant, texte: brute.slice(1).trim() });
    }
  }
  return {
    nouvelles: sansEquivalent(ajoutees, retirees),
    disparues: sansEquivalent(retirees, ajoutees),
  };
}

/** Trouvailles dans les lignes d'un lot (fichiers de la zone autorisée seulement). */
export function controlerLignes(diff) {
  const trouvailles = [];
  const { nouvelles, disparues } = lignesDuDiff(diff);
  for (const l of nouvelles) {
    const zone = classer(l.chemin);
    if (zone.zone !== 'autorisee' || !l.texte) continue;
    const estDart = l.chemin.endsWith('.dart');
    const listes = [];
    if (estDart) listes.push(MOTIFS_SERVEUR, MOTIFS_FIGES);
    if (zone.restreint === 'index') listes.push(MOTIFS_INDEX);
    for (const motifs of listes) {
      for (const motif of motifs) {
        if (motif.regex.test(l.texte)) trouvailles.push({ chemin: l.chemin, ligne: l.ligne, motif: motif.nom, sens: 'ajoutée' });
      }
    }
  }
  for (const l of disparues) {
    const zone = classer(l.chemin);
    if (zone.zone !== 'autorisee' || !l.chemin.endsWith('.dart')) continue;
    for (const motif of MOTIFS_FIGES) {
      if (motif.regex.test(l.texte)) trouvailles.push({ chemin: l.chemin, ligne: 0, motif: motif.nom, sens: 'retirée' });
    }
  }
  return trouvailles;
}

function git(racine, ...args) {
  const r = spawnSync('git', ['-C', racine, ...args], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} : ${r.stderr.trim()}`);
  return r.stdout;
}

export const racineDepot = (depuis = process.cwd()) => git(depuis, 'rev-parse', '--show-toplevel').trim();

function lireContenu(racine, ref, chemin) {
  try {
    return git(racine, 'show', `${ref}:${chemin}`);
  } catch {
    return null;
  }
}

/**
 * Fichiers d'un lot : [{ statut, chemin }]. Les renommages sont vus comme
 * une suppression et un ajout, pour que les DEUX chemins soient jugés.
 */
function fichiersModifies(sortieNameStatus) {
  const parts = sortieNameStatus.split('\0').filter(Boolean);
  const fichiers = [];
  for (let i = 0; i + 1 < parts.length; i += 2) fichiers.push({ statut: parts[i], chemin: parts[i + 1] });
  return fichiers;
}

/**
 * Analyse un lot : classement de chaque fichier, suppressions de tests,
 * tests de logique (hors widgets) et lignes nouvelles.
 * `contenu(chemin)` rend le contenu final du fichier (null si supprimé).
 */
export function analyserLot({ fichiers, diff, contenu }) {
  const lignes = fichiers.map(({ statut, chemin }) => {
    const zone = classer(chemin);
    const entree = { statut, chemin: normaliser(chemin), ...zone };
    if (zone.zone === 'autorisee' && zone.test) {
      if (statut === 'D') {
        Object.assign(entree, { zone: 'interdite', raison: 'suppression d’un test : un lot de design ne retire pas de garde-fou' });
      } else {
        const texte = contenu(chemin);
        if (texte !== null && !/\btestWidgets\s*\(/.test(texte)) {
          Object.assign(entree, { zone: 'interdite', raison: 'test de logique (sans widget) : hors du visuel' });
        }
      }
    }
    return entree;
  });
  const trouvailles = controlerLignes(diff);
  return {
    fichiers: lignes,
    trouvailles,
    autorisees: lignes.filter((f) => f.zone === 'autorisee').length,
    interdites: lignes.filter((f) => f.zone === 'interdite').length,
    horsZone: lignes.filter((f) => f.zone === 'hors_zone').length,
    conforme: lignes.every((f) => f.zone === 'autorisee') && trouvailles.length === 0,
  };
}

const ETIQUETTE = { autorisee: 'autorisé ', interdite: 'INTERDIT ', hors_zone: 'HORS ZONE' };

function rapporterLot(titre, bilan) {
  console.log(
    `Lot de design · ${titre} : ${bilan.fichiers.length} fichier(s), ${bilan.autorisees} autorisé(s), ${bilan.interdites} interdit(s), ${bilan.horsZone} hors zone, ${bilan.trouvailles.length} ligne(s) refusée(s).`,
  );
  for (const f of bilan.fichiers) {
    const limite = f.zone === 'autorisee' && f.limite ? ' · cas limite (paiement, recharge ou connexion : habillage seulement)' : '';
    console.log(`  ${ETIQUETTE[f.zone]} ${f.statut} ${f.chemin} · ${f.raison}${limite}`);
    if (f.zone !== 'autorisee') {
      annoncerErreur('Lot de design hors zone', `${f.chemin} : ${f.raison}`);
    }
  }
  for (const t of bilan.trouvailles) {
    console.log(`  LIGNE REFUSÉE ${t.chemin}${t.ligne ? `:${t.ligne}` : ''} · ${t.motif} (${t.sens})`);
    annoncerErreur('Lot de design : ligne refusée', `${t.chemin}${t.ligne ? `:${t.ligne}` : ''} · ${t.motif} (${t.sens})`);
  }
  return bilan.conforme ? 0 : 1;
}

/** Fichiers et lignes entre deux commits. */
export function lotEntre(racine, base, tete) {
  const fichiers = fichiersModifies(git(racine, 'diff', '--name-status', '-z', '--no-renames', base, tete));
  const diff = git(racine, 'diff', '--no-color', '-U0', '--no-renames', base, tete);
  return analyserLot({ fichiers, diff, contenu: (chemin) => lireContenu(racine, tete, chemin) });
}

/** Fichiers et lignes d'un seul commit. */
export function lotDuCommit(racine, sha) {
  const fichiers = fichiersModifies(git(racine, 'diff-tree', '--root', '-r', '--no-commit-id', '--name-status', '-z', '--no-renames', sha));
  const diff = git(racine, 'show', '--no-color', '-U0', '--no-renames', '--format=', sha);
  return analyserLot({ fichiers, diff, contenu: (chemin) => lireContenu(racine, sha, chemin) });
}

/** Un commit se déclare lot de design par la ligne « Lot-Design: oui » de son message. */
export const estLotDeDesign = (message) => /^Lot-Design:\s*(?:oui|yes|true)\s*$/im.test(message);

/** Commits (sans fusion) de base..tete déclarés comme lots de design. */
export function commitsDeDesign(racine, base, tete) {
  const shas = git(racine, 'rev-list', '--reverse', '--no-merges', `${base}..${tete}`).split('\n').filter(Boolean);
  return shas.filter((sha) => estLotDeDesign(git(racine, 'log', '-1', '--format=%B', sha)));
}

// ---- Intégrité des outils installés (.claude/) -------------------------------------------

const EXTENSIONS_TEXTE = new Set(['.md', '.csv']);
const SANS_EXTENSION_ADMISE = new Set(['LICENSE']);

const sha256 = (chemin) => createHash('sha256').update(readFileSync(chemin)).digest('hex');

export function chargerManifeste(fichier = path.join(DOSSIER_SECURITE, 'outils_externes.json')) {
  const contenu = JSON.parse(readFileSync(fichier, 'utf8'));
  if (!Array.isArray(contenu.outils)) throw new Error('outils_externes.json : liste « outils » absente');
  return contenu;
}

/**
 * Tout ce qui est sous .claude/ (et tout .mcp.json) doit être prévu par le
 * manifeste, être du texte (.md, .csv, LICENSE), ni exécutable ni lien, et
 * avoir exactement l'empreinte enregistrée. Un outil sans entrée au manifeste
 * n'a pas été lu en entier ni validé par le client : il est refusé.
 */
export function controlerIntegrite(racine, manifeste = chargerManifeste()) {
  const erreurs = [];
  const listes = git(racine, 'ls-files', '--cached', '--others', '--exclude-standard', '-z').split('\0').filter(Boolean);
  const claude = listes.filter((f) => f.startsWith('.claude/'));
  const prevus = new Map();
  for (const outil of manifeste.outils) {
    for (const [relatif, infos] of Object.entries(outil.fichiers ?? {})) {
      prevus.set(`${outil.dossier}/${relatif}`, { outil: outil.nom, ...infos });
    }
    if (!/^[0-9a-f]{40}$/.test(outil.commit ?? '')) erreurs.push(`${outil.nom} : commit figé absent ou invalide dans le manifeste`);
    if (!outil.licence) erreurs.push(`${outil.nom} : licence non renseignée dans le manifeste`);
  }
  for (const f of listes.filter((x) => /(?:^|\/)\.mcp\.json$/.test(x))) {
    erreurs.push(`${f} : serveur MCP interdit (code exécuté par l’agent)`);
  }
  for (const f of claude) {
    const chemin = path.join(racine, f);
    const info = lstatSync(chemin);
    const nom = path.basename(f);
    const ext = path.extname(f).toLowerCase();
    if (info.isSymbolicLink()) erreurs.push(`${f} : lien symbolique interdit`);
    else if (info.mode & 0o111) erreurs.push(`${f} : fichier exécutable interdit`);
    if (ext === '' ? !SANS_EXTENSION_ADMISE.has(nom) : !EXTENSIONS_TEXTE.has(ext)) {
      erreurs.push(`${f} : seul du texte (.md, .csv, LICENSE) est admis dans un outil externe`);
    }
    if (!prevus.has(f)) erreurs.push(`${f} : fichier non prévu par securite/outils_externes.json`);
  }
  for (const [f, infos] of prevus) {
    const chemin = path.join(racine, f);
    if (!existsSync(chemin)) {
      erreurs.push(`${f} : prévu par le manifeste mais absent`);
      continue;
    }
    if (!/^[0-9a-f]{64}$/.test(infos.sha256 ?? '')) {
      erreurs.push(`${f} : empreinte absente ou invalide dans le manifeste`);
    } else if (sha256(chemin) !== infos.sha256) {
      erreurs.push(`${f} : contenu différent de l’empreinte du manifeste (fichier modifié depuis la validation)`);
    }
  }
  for (const outil of manifeste.outils) {
    const skill = path.join(racine, outil.dossier, 'SKILL.md');
    if (existsSync(skill) && !readFileSync(skill, 'utf8').includes('securite/ZONES_DESIGN.md')) {
      erreurs.push(`${outil.dossier}/SKILL.md : ne rappelle plus la règle des zones (securite/ZONES_DESIGN.md)`);
    }
  }
  return { erreurs, fichiers: claude.length };
}

function principal(argv) {
  const [mode, base, tete] = argv;
  try {
    if (mode === 'diff') {
      if (!base || !tete) throw new Error('Usage : outils_design.mjs diff <base> <tete>');
      return rapporterLot(`${base.slice(0, 7)}..${tete.slice(0, 7)}`, lotEntre(racineDepot(), base, tete));
    }
    if (mode === 'commits') {
      if (!base || !tete || /^0+$/.test(base)) {
        annoncerAvertissement('Lots de design', 'Pas de commit de départ (nouvelle branche ou lancement manuel) : contrôle des lots sauté.');
        return 0;
      }
      const racine = racineDepot();
      let shas;
      try {
        shas = commitsDeDesign(racine, base, tete);
      } catch (e) {
        annoncerAvertissement('Lots de design', `Commits non analysés (${String(e.message ?? e).slice(0, 160)}).`);
        return 0;
      }
      console.log(`Lots de design · ${base.slice(0, 7)}..${tete.slice(0, 7)} : ${shas.length} commit(s) déclaré(s) « Lot-Design: oui ».`);
      let code = 0;
      for (const sha of shas) code = Math.max(code, rapporterLot(`commit ${sha.slice(0, 7)}`, lotDuCommit(racine, sha)));
      return code;
    }
    if (mode === 'integrite') {
      const { erreurs, fichiers } = controlerIntegrite(racineDepot());
      console.log(`Outils externes · ${fichiers} fichier(s) sous .claude/ : ${erreurs.length} écart(s).`);
      for (const e of erreurs) {
        console.log(`  ${e}`);
        annoncerErreur('Outil externe non conforme', e);
      }
      return erreurs.length === 0 ? 0 : 1;
    }
  } catch (e) {
    console.error(String(e.message ?? e));
    return 2;
  }
  console.error('Usage : outils_design.mjs diff <base> <tete> | commits <base> <tete> | integrite');
  return 2;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exit(principal(process.argv.slice(2)));
