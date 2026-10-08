#!/usr/bin/env node
// Garde-fou contre les fuites de secrets (clés, jetons, comptes de service) :
//
//   node securite/garde_fuites.mjs fichiers              fichiers suivis par git
//   node securite/garde_fuites.mjs diff <base> <tete>    lignes ajoutées entre deux commits
//   node securite/garde_fuites.mjs dossier <chemin>      site compilé (build/web)
//   node securite/garde_fuites.mjs apk <fichier.apk>     application Android compilée
//
// Bloque (code 1) à la première trouvaille. Le dépôt GitHub est PUBLIC et
// les journaux de la CI aussi : une trouvaille n'est donc jamais affichée en
// entier (4 premiers caractères et longueur seulement).
//
// Clés Google : seules sont admises la clé web Firebase de
// lib/firebase_options.dart (publique par conception) et les clés de carte
// restreintes que la CI injecte à la compilation (variables
// GOOGLE_MAPS_WEB_KEY / GOOGLE_MAPS_ANDROID_KEY, ou CLES_PUBLIQUES_AUTORISEES
// séparées par des virgules). Toute autre clé AIza… est une fuite.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { annoncerAvertissement, annoncerErreur } from './commun.mjs';

/** Motifs à fort signal : peu de faux positifs, car un blocage arrête le déploiement. */
export const MOTIFS = [
  { nom: 'clé privée (PEM)', regex: /-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY(?: BLOCK)?-----/g },
  { nom: 'compte de service Google (JSON)', regex: /"private_key_id"\s*:\s*"[0-9a-f]{20,}"/g },
  { nom: 'jeton GitHub', regex: /\bgh[pousr]_[A-Za-z0-9]{36,}\b/g },
  { nom: 'jeton GitHub (fin granulaire)', regex: /\bgithub_pat_[A-Za-z0-9_]{50,}\b/g },
  { nom: 'clé AWS', regex: /\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/g },
  { nom: 'clé secrète de paiement (sk_live_…)', regex: /\b[sr]k_live_[0-9A-Za-z]{20,}\b/g },
  { nom: 'jeton Slack', regex: /\bxox[abprso]-[0-9A-Za-z-]{10,}\b/g },
  { nom: 'clé Wave (format supposé)', regex: /\bwave_[a-z]{2}_(?:prod|live|test|sandbox)_[A-Za-z0-9_-]{16,}\b/gi },
  { nom: 'jeton JWT', regex: /\beyJ[A-Za-z0-9_-]{15,}\.eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\b/g },
  {
    nom: 'adresse de service avec identifiants',
    regex: /\b[a-z][a-z0-9+.-]*:\/\/[^\s:@/'"]+:[^\s@/'"]{4,}@(?!localhost\b|127\.0\.0\.1\b|\[::1\])[^\s/'"]+/gi,
  },
  { nom: 'clé API Google non autorisée', regex: /\bAIza[0-9A-Za-z_-]{35}\b/g, google: true },
];

/** Secrets du serveur : leur NOM même n'a rien à faire dans l'app ni dans le site compilé. */
export const NOMS_SECRETS_SERVEUR =
  /\b(?:WAVE_API_KEY|WAVE_WEBHOOK_SECRET|ORANGE_MONEY_[A-Z_]*(?:SECRET|KEY)|GOOGLE_MAPS_API_KEY|FIREBASE_SERVICE_ACCOUNT)\b/g;

/** Dossiers du dépôt (relatifs à la racine) qui partent chez l'utilisateur. */
const DOSSIERS_CLIENT = ['mobile/lib/', 'mobile/web/', 'mobile/android/', 'mobile/ios/'];

const EXTENSIONS_IGNOREES = new Set([
  '.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.ttf', '.otf', '.woff', '.woff2', '.jar', '.zip', '.gz',
  '.pdf', '.mp3', '.mp4', '.wasm', '.aab',
]);
const TAILLE_MAX_OCTETS = 8 * 1024 * 1024;

/** 4 premiers caractères et longueur : assez pour retrouver la ligne, jamais assez pour s'en servir. */
export function masquer(valeur) {
  return `${valeur.slice(0, 4)}… (${valeur.length} car.)`;
}

/** Clés Google publiques admises : firebase_options.dart + variables d'environnement. */
export function clesAutorisees(racine, env = process.env) {
  const cles = new Set();
  try {
    const source = readFileSync(path.join(racine, 'mobile/lib/firebase_options.dart'), 'utf8');
    for (const m of source.matchAll(/apiKey:\s*'(AIza[0-9A-Za-z_-]{35})'/g)) cles.add(m[1]);
  } catch {
    /* pas de fichier : aucune clé Firebase admise */
  }
  for (const nom of ['GOOGLE_MAPS_WEB_KEY', 'GOOGLE_MAPS_ANDROID_KEY']) if (env[nom]) cles.add(env[nom].trim());
  for (const cle of (env.CLES_PUBLIQUES_AUTORISEES ?? '').split(',')) if (cle.trim()) cles.add(cle.trim());
  return cles;
}

/**
 * Cherche les secrets dans un texte. [cheminRelatif] (depuis la racine du
 * dépôt) active le contrôle des noms de secrets du serveur pour le code
 * client ; [client] le force (site compilé, APK).
 */
export function scannerTexte(texte, { chemin = '', autorisees = new Set(), client = false, decalageLigne = 0 } = {}) {
  const trouvailles = [];
  const ligneDe = (indice) => decalageLigne + texte.slice(0, indice).split('\n').length;
  for (const motif of MOTIFS) {
    for (const m of texte.matchAll(motif.regex)) {
      if (motif.google && autorisees.has(m[0])) continue;
      trouvailles.push({ chemin, ligne: ligneDe(m.index), motif: motif.nom, extrait: masquer(m[0]) });
    }
  }
  if (client || DOSSIERS_CLIENT.some((d) => chemin.startsWith(d))) {
    for (const m of texte.matchAll(NOMS_SECRETS_SERVEUR)) {
      trouvailles.push({ chemin, ligne: ligneDe(m.index), motif: 'nom de secret du serveur dans le code client', extrait: m[0] });
    }
  }
  return trouvailles;
}

function lireFichier(chemin) {
  if (EXTENSIONS_IGNOREES.has(path.extname(chemin).toLowerCase())) return null;
  if (statSync(chemin).size > TAILLE_MAX_OCTETS) return null;
  return readFileSync(chemin).toString('latin1');
}

function git(racine, ...args) {
  const r = spawnSync('git', ['-C', racine, ...args], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} : ${r.stderr.trim()}`);
  return r.stdout;
}

export function racineDepot(depuis = process.cwd()) {
  return git(depuis, 'rev-parse', '--show-toplevel').trim();
}

/** Fichiers suivis par git (nom relatif à la racine). */
export function scannerFichiersSuivis(racine, env = process.env) {
  const autorisees = clesAutorisees(racine, env);
  const trouvailles = [];
  let lus = 0;
  for (const chemin of git(racine, 'ls-files', '-z').split('\0').filter(Boolean)) {
    const texte = lireFichier(path.join(racine, chemin));
    if (texte === null) continue;
    lus++;
    trouvailles.push(...scannerTexte(texte, { chemin, autorisees }));
  }
  return { lus, trouvailles };
}

/** Lignes ajoutées entre deux commits (un secret poussé puis retiré compte aussi). */
export function scannerDiff(racine, base, tete, env = process.env) {
  const autorisees = clesAutorisees(racine, env);
  const trouvailles = [];
  let chemin = '';
  let ligne = 0;
  let ajoutees = 0;
  const sortie = git(racine, 'diff', '--no-color', '-U0', '--diff-filter=AM', base, tete);
  for (const brute of sortie.split('\n')) {
    let m;
    if ((m = /^\+\+\+ b\/(.*)$/.exec(brute))) {
      chemin = m[1];
    } else if ((m = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(brute))) {
      ligne = Number(m[1]);
    } else if (brute.startsWith('+') && !brute.startsWith('+++')) {
      ajoutees++;
      if (!EXTENSIONS_IGNOREES.has(path.extname(chemin).toLowerCase())) {
        trouvailles.push(...scannerTexte(brute.slice(1), { chemin, autorisees, decalageLigne: ligne - 1 }));
      }
      ligne++;
    }
  }
  return { ajoutees, trouvailles };
}

function parcourir(dossier, visiter) {
  for (const entree of readdirSync(dossier, { withFileTypes: true })) {
    const chemin = path.join(dossier, entree.name);
    if (entree.isDirectory()) parcourir(chemin, visiter);
    else if (entree.isFile()) visiter(chemin);
  }
}

/** Site compilé ou APK décompressé : tout fichier est scanné, le code est « client ». */
export function scannerDossier(dossier, env = process.env, racine = process.cwd()) {
  const autorisees = clesAutorisees(racine, env);
  const trouvailles = [];
  let lus = 0;
  parcourir(dossier, (chemin) => {
    if (statSync(chemin).size > TAILLE_MAX_OCTETS * 4) return;
    lus++;
    const texte = readFileSync(chemin).toString('latin1');
    trouvailles.push(...scannerTexte(texte, { chemin: path.relative(dossier, chemin), autorisees, client: true }));
  });
  return { lus, trouvailles };
}

function rapporter(titre, bilan, unite = 'fichiers') {
  const ligneFichier = (t) => (t.ligne ? `${t.chemin}:${t.ligne}` : t.chemin);
  console.log(`Garde-fou secrets · ${titre} : ${bilan.lus ?? bilan.ajoutees} ${unite} lus, ${bilan.trouvailles.length} trouvaille(s).`);
  for (const t of bilan.trouvailles) {
    console.log(`  ${ligneFichier(t)} · ${t.motif} · ${t.extrait}`);
    console.log(
      `::error file=${t.chemin},${t.ligne ? `line=${t.ligne},` : ''}title=Secret possible::${t.motif} (${t.extrait})`,
    );
  }
  if (bilan.trouvailles.length > 0) {
    annoncerErreur(
      'Fuite de secret possible',
      'Un secret a peut-être été publié : le dépôt et ses journaux sont publics. Retirez-le, puis RÉVOQUEZ-LE chez son émetteur sans attendre.',
    );
  }
  return bilan.trouvailles.length > 0 ? 1 : 0;
}

function principal(argv) {
  const [mode, a, b] = argv;
  try {
    if (mode === 'fichiers') {
      const racine = racineDepot();
      return rapporter('fichiers du dépôt', scannerFichiersSuivis(racine));
    }
    if (mode === 'diff') {
      const zeros = /^0+$/;
      if (!a || !b || zeros.test(a)) {
        annoncerAvertissement('Garde-fou secrets', 'Pas de commit de départ (nouvelle branche ou lancement manuel) : analyse des lignes ajoutées sautée.');
        return 0;
      }
      let bilan;
      try {
        bilan = scannerDiff(racineDepot(), a, b);
      } catch (e) {
        // Commit de départ introuvable (push forcé, historique réécrit) : le
        // contrôle « fichiers » couvre l'état actuel ; on le dit sans bloquer.
        annoncerAvertissement('Garde-fou secrets', `Lignes ajoutées non analysées (${String(e.message ?? e).slice(0, 160)}).`);
        return 0;
      }
      return rapporter(`lignes ajoutées ${a.slice(0, 7)}..${b.slice(0, 7)}`, bilan, 'lignes ajoutées');
    }
    if (mode === 'dossier' && a) {
      return rapporter(`dossier ${a}`, scannerDossier(a, process.env, racineDepot()));
    }
    if (mode === 'apk' && a) {
      const tmp = mkdtempSync(path.join(tmpdir(), 'apk-'));
      try {
        const r = spawnSync('unzip', ['-qq', '-o', a, '-d', tmp], { encoding: 'utf8' });
        if (r.status !== 0 && r.status !== 1) {
          annoncerAvertissement('Garde-fou secrets', `APK non analysé (unzip : ${(r.stderr || r.error?.message || 'échec').slice(0, 200)}).`);
          return 0;
        }
        return rapporter(`APK ${path.basename(a)}`, scannerDossier(tmp, process.env, racineDepot()));
      } finally {
        rmSync(tmp, { recursive: true, force: true });
      }
    }
  } catch (e) {
    console.error(String(e.message ?? e));
    return 2;
  }
  console.error('Usage : garde_fuites.mjs fichiers | diff <base> <tete> | dossier <chemin> | apk <fichier>');
  return 2;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exit(principal(process.argv.slice(2)));
