#!/usr/bin/env node
// Essai de restauration d'une sauvegarde Firestore dans une base TEMPORAIRE.
//
//   node securite/restauration.mjs essai      restaure la dernière sauvegarde dans « restauration-essai-<n° du run> »,
//                                             compte les documents (collection par collection) dans cette base et
//                                             dans la base en ligne, et affiche la comparaison
//   node securite/restauration.mjs nettoyer   supprime la base d'essai de ce run (sans effet si elle n'existe pas)
//
// Variable BASE_ESSAI_EXISTANTE (« restauration-essai-<numéro> » d'un essai précédent resté en place) : `essai` ne
// restaure rien, il compte cette base ; `nettoyer` la supprime.
//   node securite/restauration.mjs lister     (lecture seule) bases du projet, et bases d'essai restées en place
//
// Une sauvegarde jamais restaurée n'est pas prouvée. Une restauration ne remplace
// JAMAIS la base en ligne : elle crée une nouvelle base. Google annonce l'opération
// terminée avant que la base réponde (« database is undergoing a restore ») : on
// attend qu'elle serve, et la suppression attend aussi. Garde-fous :
// - la base en ligne `(default)` n'est jamais écrite ni supprimée : seulement lue (comptages) ;
// - une base n'est créée ou supprimée que si son identifiant est « restauration-essai-<numéro> » ;
// - avant de créer quoi que ce soit, le droit de la supprimer est vérifié (pas de base orpheline) ;
// - la suppression se fait dans une étape à part, qui tourne même si l'essai a échoué.
//
// Le jeton Google vient de JETON_GOOGLE (jamais affiché). Code 0 : essai réussi ; 1 : à regarder ; 2 : usage.
import { execFileSync } from 'node:child_process';
import { appendFileSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { DOSSIER_SECURITE, annoncerAvertissement, annoncerErreur, annoncerNotice } from './commun.mjs';
import { DROITS_RESTAURATION, PROJET, appeler, lireSauvegardes, testerDroit } from './sauvegardes.mjs';

const FIRESTORE = 'https://firestore.googleapis.com/v1';
const BASE_EN_LIGNE = '(default)';

export const PREFIXE_BASE_ESSAI = 'restauration-essai-';
const MOTIF_BASE_ESSAI = /^restauration-essai-[0-9]{1,20}$/;

/** Attente entre deux lectures d'une opération Google, et nombre maximal de lectures (30 minutes). */
const ATTENTE_MS = 15_000;
const LECTURES_MAX = 120;

// ---------------------------------------------------------------------
// Jeton Google : valable une heure, or une restauration suivie de la suppression peut durer plus longtemps
// ---------------------------------------------------------------------

/**
 * Enveloppe un `fetch` : si Google répond 401 (jeton expiré), un jeton neuf est demandé à [renouveler] et la
 * demande est refaite une fois ; les demandes suivantes utilisent ce jeton neuf.
 */
export function fetcherRenouvelable(fetcher, renouveler) {
  let neuf = null;
  const avec = (options, jeton) => ({ ...options, headers: { ...options?.headers, authorization: `Bearer ${jeton}` } });
  return async (url, options = {}) => {
    const reponse = await fetcher(url, neuf ? avec(options, neuf) : options);
    if (reponse.status !== 401) return reponse;
    try {
      neuf = await renouveler();
    } catch {
      return reponse;
    }
    return fetcher(url, avec(options, neuf));
  };
}

/** Jeton neuf demandé à gcloud (déjà authentifié par l'étape de connexion à Google) ; masqué dans les journaux. */
export function renouvelerParGcloud() {
  const jeton = execFileSync('gcloud', ['auth', 'print-access-token'], { encoding: 'utf8' }).trim();
  console.log(`::add-mask::${jeton}`);
  return jeton;
}

// ---------------------------------------------------------------------
// Garde-fous
// ---------------------------------------------------------------------

/** Identifiant de la base d'essai de ce run ; lève une erreur hors GitHub Actions (pas de numéro de run). */
export function idBaseEssai(env) {
  const run = String(env.GITHUB_RUN_ID ?? '');
  if (!/^[0-9]{1,20}$/.test(run)) throw new Error('Numéro de run introuvable (GITHUB_RUN_ID) : cet essai ne se lance que depuis GitHub Actions.');
  return `${PREFIXE_BASE_ESSAI}${run}`;
}

/**
 * La base visée par ce run : celle d'un essai précédent resté en place (BASE_ESSAI_EXISTANTE, vérifiée comme
 * toute base d'essai), sinon la base d'essai de ce run, qui n'existe pas encore.
 */
export function baseCible(env) {
  const existante = String(env.BASE_ESSAI_EXISTANTE ?? '').trim();
  if (existante) return { id: verifierBaseEssai(existante), existante: true };
  return { id: idBaseEssai(env), existante: false };
}

/** Refuse tout identifiant qui n'est pas celui d'une base d'essai (jamais `(default)`). */
export function verifierBaseEssai(id) {
  if (!MOTIF_BASE_ESSAI.test(String(id))) {
    throw new Error(`Base refusée : « ${id} » n'est pas une base d'essai (${PREFIXE_BASE_ESSAI}<numéro>). La base en ligne n'est jamais touchée.`);
  }
  return id;
}

const urlBase = (id) => `${FIRESTORE}/projects/${PROJET}/databases/${id}`;
const detail = (r) => r.json?.error?.message ?? String(r.texte ?? '').slice(0, 200);

/** Google répond ainsi tant que la restauration d'une base n'est pas vraiment finie. */
const encoreEnRestauration = (texte) => /restore/i.test(String(texte ?? ''));

/** Une base restaurée met du temps à répondre après la fin de l'opération : 20 minutes au plus. */
const ATTENTE_SERVICE_MAX = 80;
/** Suppression refusée pendant la restauration : 20 minutes au plus, une tentative toutes les 20 secondes. */
const ATTENTE_SUPPRESSION_MAX = 60;
const ATTENTE_SUPPRESSION_MS = 20_000;

// ---------------------------------------------------------------------
// Collections à compter
// ---------------------------------------------------------------------

/**
 * Noms de collections déclarés dans les règles de sécurité (racines et sous-collections :
 * `match /appareils/{uid}/jetons/{jeton}` donne « appareils » et « jetons »).
 */
export function collectionsDesRegles(texteRegles) {
  const noms = new Set();
  for (const m of String(texteRegles).matchAll(/match\s+((?:\/\{[^}]+\}|\/[^\s{/]+)+)/g)) {
    for (const segment of m[1].split('/')) {
      if (segment && !segment.startsWith('{') && segment !== 'databases' && segment !== 'documents') noms.add(segment);
    }
  }
  return [...noms].sort();
}

export async function listerCollectionsRacine(fetcher, jeton, idBase) {
  const r = await appeler(fetcher, jeton, 'POST', `${urlBase(idBase)}/documents:listCollectionIds`, { pageSize: 200 });
  if (!r.ok) return { erreur: `Lecture des collections de ${idBase} impossible (HTTP ${r.statut}) : ${detail(r)}` };
  return { collections: Array.isArray(r.json?.collectionIds) ? r.json.collectionIds : [] };
}

/** Nombre de documents portant ce nom de collection, à n'importe quel niveau (lecture seule, comptage côté Google). */
export async function compterDocuments(fetcher, jeton, idBase, collectionId) {
  const r = await appeler(fetcher, jeton, 'POST', `${urlBase(idBase)}/documents:runAggregationQuery`, {
    structuredAggregationQuery: {
      structuredQuery: { from: [{ collectionId, allDescendants: true }] },
      aggregations: [{ alias: 'n', count: {} }],
    },
  });
  if (!r.ok) return { erreur: `Comptage de « ${collectionId} » dans ${idBase} impossible (HTTP ${r.statut}) : ${detail(r)}` };
  const reponse = Array.isArray(r.json) ? r.json.find((element) => element?.result) : null;
  const valeur = reponse?.result?.aggregateFields?.n?.integerValue;
  // Une valeur 0 peut ne pas figurer dans la réponse.
  const n = valeur === undefined ? 0 : Number(valeur);
  return Number.isFinite(n) && n >= 0 ? { n } : { erreur: `Comptage de « ${collectionId} » illisible dans ${idBase}.` };
}

/** Comme `compterDocuments`, en patientant tant que Google répond que la base est en cours de restauration. */
export async function compterAvecAttente(fetcher, jeton, idBase, collectionId, pause) {
  let compte = await compterDocuments(fetcher, jeton, idBase, collectionId);
  for (let essai = 0; compte.erreur && encoreEnRestauration(compte.erreur) && essai < ATTENTE_SERVICE_MAX; essai++) {
    await pause(ATTENTE_MS);
    compte = await compterDocuments(fetcher, jeton, idBase, collectionId);
  }
  return compte;
}

/**
 * Attend que la base restaurée réponde : l'opération de restauration est annoncée terminée avant que la base serve
 * (« Cannot serve requests when the database is undergoing a restore »). Rend ses collections de premier niveau.
 */
export async function attendreBaseServie(fetcher, jeton, idBase, pause) {
  for (let essai = 0; essai < ATTENTE_SERVICE_MAX; essai++) {
    const r = await listerCollectionsRacine(fetcher, jeton, idBase);
    if (!r.erreur) return { collections: r.collections, attentes: essai };
    if (!encoreEnRestauration(r.erreur)) return { erreur: r.erreur };
    await pause(ATTENTE_MS);
  }
  return { erreur: `La base ${idBase} ne répond toujours pas au bout de ${Math.round((ATTENTE_SERVICE_MAX * ATTENTE_MS) / 60000)} minutes : restauration encore en cours chez Google.` };
}

// ---------------------------------------------------------------------
// Comparaison
// ---------------------------------------------------------------------

/**
 * Collections qui existaient et contenaient des documents bien avant la sauvegarde : vides après restauration,
 * c'est un vrai problème. Une autre collection vide a pu naître depuis (le départ exact des courses, `prive`,
 * n'existe que depuis la publication du 9 octobre au soir, après la première sauvegarde).
 */
export const COLLECTIONS_ESSENTIELLES = ['users', 'courses', 'commandes', 'portefeuilles', 'profils_publics', 'chats', 'messages'];

/**
 * Compare les comptages de la base restaurée et de la base en ligne (prise depuis, donc
 * un peu plus récente : des documents ont pu être créés ou supprimés entre-temps).
 * - `identique` : même nombre ;
 * - `plus-en-ligne` : des documents créés depuis la sauvegarde (normal) ;
 * - `moins-en-ligne` : des documents supprimés depuis la sauvegarde (jetons, sessions...) ;
 * - `vide-recente` : rien de restauré dans une collection née peut-être depuis la sauvegarde : à expliquer ;
 * - `vide` : rien de restauré dans une collection essentielle alors qu'elle contient des documents en ligne : suspect.
 * Verdict : `ok` (restauration plausible), `suspect` (une collection essentielle vide), `inconcluant`
 * (aucun document nulle part : rien n'est prouvé).
 */
export function comparerComptages(restauree, enLigne) {
  const noms = [...new Set([...Object.keys(restauree), ...Object.keys(enLigne)])].sort();
  const lignes = noms.map((nom) => {
    const r = restauree[nom] ?? 0;
    const l = enLigne[nom] ?? 0;
    let statut = 'identique';
    if (r !== l) {
      if (r === 0) statut = COLLECTIONS_ESSENTIELLES.includes(nom) ? 'vide' : 'vide-recente';
      else statut = r < l ? 'plus-en-ligne' : 'moins-en-ligne';
    }
    return { nom, restauree: r, enLigne: l, ecart: l - r, statut };
  });
  const totalRestauree = lignes.reduce((somme, ligne) => somme + ligne.restauree, 0);
  const totalEnLigne = lignes.reduce((somme, ligne) => somme + ligne.enLigne, 0);
  const verdict = lignes.some((ligne) => ligne.statut === 'vide') ? 'suspect' : totalRestauree === 0 && totalEnLigne === 0 ? 'inconcluant' : 'ok';
  return { lignes, totalRestauree, totalEnLigne, verdict };
}

const LIBELLE_STATUT = {
  identique: 'identique',
  'plus-en-ligne': 'créés depuis la sauvegarde',
  'moins-en-ligne': 'supprimés depuis la sauvegarde',
  'vide-recente': 'vide : collection née depuis la sauvegarde ?',
  vide: 'VIDE dans la restauration',
};

export function resumeMarkdown({ sauvegarde, idBase, comparaison, collectionsIllisibles }) {
  const verdict = { ok: 'RÉUSSI', suspect: 'À REGARDER', inconcluant: 'NON CONCLUANT' }[comparaison.verdict];
  const lignes = [
    `## Essai de restauration · ${verdict}`,
    '',
    `Sauvegarde du **${sauvegarde.snapshotTime}** restaurée dans la base temporaire \`${idBase}\` (supprimée ensuite). La base en ligne n'a pas été touchée.`,
    '',
    `Documents : **${comparaison.totalRestauree}** dans la base restaurée, **${comparaison.totalEnLigne}** dans la base en ligne aujourd'hui.`,
    '',
    '| Collection | Restaurée | En ligne | Écart | Lecture |',
    '|---|---:|---:|---:|---|',
  ];
  for (const ligne of comparaison.lignes) {
    lignes.push(`| ${ligne.nom} | ${ligne.restauree} | ${ligne.enLigne} | ${ligne.ecart > 0 ? '+' : ''}${ligne.ecart} | ${LIBELLE_STATUT[ligne.statut]} |`);
  }
  if (collectionsIllisibles.length > 0) lignes.push('', `Non comptées (erreur) : ${collectionsIllisibles.join(', ')}.`);
  lignes.push('', 'Les écarts positifs sont normaux : la base en ligne a continué à vivre depuis la sauvegarde.');
  return `${lignes.join('\n')}\n`;
}

// ---------------------------------------------------------------------
// Opérations Google (restauration, suppression)
// ---------------------------------------------------------------------

async function attendreOperation(fetcher, jeton, nom, pause) {
  for (let lecture = 0; lecture < LECTURES_MAX; lecture++) {
    const r = await appeler(fetcher, jeton, 'GET', `${FIRESTORE}/${nom}`);
    if (!r.ok) return { erreur: `Suivi de l'opération impossible (HTTP ${r.statut}) : ${detail(r)}` };
    if (r.json?.done) {
      return r.json.error ? { erreur: `Google a refusé l'opération : ${r.json.error.message ?? JSON.stringify(r.json.error)}` } : { fini: true };
    }
    await pause(ATTENTE_MS);
  }
  return { erreur: `L'opération n'est pas terminée après ${Math.round((LECTURES_MAX * ATTENTE_MS) / 60000)} minutes.` };
}

export async function restaurer(fetcher, jeton, idBase, sauvegarde, pause) {
  verifierBaseEssai(idBase);
  const r = await appeler(fetcher, jeton, 'POST', `${FIRESTORE}/projects/${PROJET}/databases:restore`, {
    databaseId: idBase,
    backup: sauvegarde.name,
  });
  if (!r.ok) return { erreur: `Restauration refusée (HTTP ${r.statut}) : ${detail(r)}` };
  if (typeof r.json?.name !== 'string') return { erreur: 'Google n\'a pas nommé l\'opération de restauration.' };
  return attendreOperation(fetcher, jeton, r.json.name, pause);
}

/** Supprime la base d'essai (et seulement elle), puis attend qu'elle ait disparu. */
export async function supprimerBaseEssai(fetcher, jeton, idBase, pause) {
  verifierBaseEssai(idBase);
  const presente = await appeler(fetcher, jeton, 'GET', urlBase(idBase));
  if (presente.statut === 404) return { dejaAbsente: true };
  if (!presente.ok) return { erreur: `Lecture de la base ${idBase} impossible (HTTP ${presente.statut}) : ${detail(presente)}` };
  // Google refuse de supprimer une base tant que sa restauration n'est pas vraiment finie : on patiente.
  let r = await appeler(fetcher, jeton, 'DELETE', urlBase(idBase));
  for (let essai = 0; !r.ok && encoreEnRestauration(detail(r)) && essai < ATTENTE_SUPPRESSION_MAX; essai++) {
    await pause(ATTENTE_SUPPRESSION_MS);
    r = await appeler(fetcher, jeton, 'DELETE', urlBase(idBase));
  }
  if (!r.ok) return { erreur: `Suppression de ${idBase} refusée (HTTP ${r.statut}) : ${detail(r)}` };
  for (let lecture = 0; lecture < 60; lecture++) {
    await pause(10_000);
    const encore = await appeler(fetcher, jeton, 'GET', urlBase(idBase));
    if (encore.statut === 404) return { supprimee: true };
  }
  return { erreur: `La base ${idBase} existe encore 10 minutes après la demande de suppression.` };
}

// ---------------------------------------------------------------------
// Commandes
// ---------------------------------------------------------------------

const AIDE_SUPPRESSION = (idBase) =>
  `Supprimez-la à la main : Google Cloud > Firestore > Bases de données > ${idBase} > Supprimer (une base laissée en place est facturée).`;

async function commandeEssai({ fetcher, jeton, env, pause, ecrireResume, lireRegles }) {
  let cible;
  try {
    cible = baseCible(env);
  } catch (e) {
    annoncerErreur('Essai de restauration impossible', e.message);
    return 1;
  }
  const idBase = cible.id;

  // 1. Tous les droits, y compris celui de supprimer : sinon on ne crée rien.
  const manquants = [];
  for (const [droit] of DROITS_RESTAURATION) {
    const test = await testerDroit(fetcher, jeton, droit);
    if (test.etat !== 'accordé') manquants.push(droit);
  }
  if (manquants.length > 0) {
    annoncerErreur('Droits manquants pour la restauration', `Le compte de déploiement n'a pas : ${manquants.join(', ')}. Rien n'a été créé.`);
    return 1;
  }

  // 2. Les sauvegardes de la base en ligne.
  const lues = await lireSauvegardes(fetcher, jeton);
  if (lues.erreur) {
    annoncerErreur('Sauvegardes illisibles', lues.erreur);
    return 1;
  }
  let sauvegarde = lues.sauvegardes[0];

  if (cible.existante) {
    // Essai précédent resté en place : on le compte et on le supprime, sans restaurer une seconde fois.
    const presente = await appeler(fetcher, jeton, 'GET', urlBase(idBase));
    if (!presente.ok) {
      annoncerErreur('Base d\'essai introuvable', `${idBase} : HTTP ${presente.statut} (${detail(presente)}). Rien n'est restauré.`);
      return 1;
    }
    const source = presente.json?.sourceInfo?.backup?.backup;
    sauvegarde = lues.sauvegardes.find((s) => s.name === source) ?? { name: source, snapshotTime: source ? `(sauvegarde ${String(source).split('/').pop()})` : 'inconnue' };
    console.log(`Base d'essai déjà restaurée : ${idBase}, issue de la sauvegarde ${sauvegarde.snapshotTime}.`);
  } else {
    if (!sauvegarde?.name) {
      annoncerErreur('Aucune sauvegarde à restaurer', 'Aucune sauvegarde prête pour la base en ligne.');
      return 1;
    }
    console.log(`Sauvegarde à restaurer : ${sauvegarde.snapshotTime} (${lues.emplacement}).`);

    // 3. La base d'essai ne doit pas exister déjà.
    const existante = await appeler(fetcher, jeton, 'GET', urlBase(idBase));
    if (existante.statut !== 404) {
      annoncerErreur('Base d\'essai déjà présente', `${idBase} existe déjà (HTTP ${existante.statut}) : rien n'est restauré.`);
      return 1;
    }

    // 4. Restauration dans la nouvelle base.
    console.log(`Restauration dans la base temporaire ${idBase}…`);
    const restauration = await restaurer(fetcher, jeton, idBase, sauvegarde, pause);
    if (restauration.erreur) {
      annoncerErreur('Restauration échouée', restauration.erreur);
      return 1;
    }
    console.log('Opération de restauration terminée.');
  }

  // 5. La base répond-elle ? Google annonce la fin de l'opération avant que la base serve.
  const service = await attendreBaseServie(fetcher, jeton, idBase, pause);
  if (service.erreur) {
    annoncerErreur('Base restaurée injoignable', service.erreur);
    return 1;
  }
  if (service.attentes > 0) console.log(`La base répond après ${service.attentes} attente(s) de ${ATTENTE_MS / 1000} s.`);

  // 6. Les collections à compter : celles des règles, plus toutes celles trouvées à la racine des deux bases.
  const noms = new Set(collectionsDesRegles(lireRegles()));
  service.collections.forEach((nom) => noms.add(nom));
  const racinesEnLigne = await listerCollectionsRacine(fetcher, jeton, BASE_EN_LIGNE);
  if (racinesEnLigne.erreur) annoncerAvertissement('Collections illisibles', racinesEnLigne.erreur);
  else racinesEnLigne.collections.forEach((nom) => noms.add(nom));

  // 7. Comptages, lecture seule.
  const restauree = {};
  const enLigne = {};
  const illisibles = [];
  for (const nom of [...noms].sort()) {
    for (const [base, cible2] of [[idBase, restauree], [BASE_EN_LIGNE, enLigne]]) {
      const compte = await compterAvecAttente(fetcher, jeton, base, nom, pause);
      if (compte.erreur) {
        illisibles.push(`${nom} (${base === idBase ? 'restaurée' : 'en ligne'})`);
        console.log(compte.erreur);
      } else {
        cible2[nom] = compte.n;
      }
    }
  }

  const comparaison = comparerComptages(restauree, enLigne);
  console.log(`\n${'Collection'.padEnd(24)}${'Restaurée'.padStart(10)}${'En ligne'.padStart(10)}${'Écart'.padStart(8)}  Lecture`);
  for (const ligne of comparaison.lignes) {
    console.log(
      `${ligne.nom.padEnd(24)}${String(ligne.restauree).padStart(10)}${String(ligne.enLigne).padStart(10)}${String(ligne.ecart).padStart(8)}  ${LIBELLE_STATUT[ligne.statut]}`,
    );
  }
  console.log(`${'TOTAL'.padEnd(24)}${String(comparaison.totalRestauree).padStart(10)}${String(comparaison.totalEnLigne).padStart(10)}`);
  ecrireResume(resumeMarkdown({ sauvegarde, idBase, comparaison, collectionsIllisibles: illisibles }));

  if (illisibles.length > 0) {
    // Un comptage manquant ne prouve rien : ni « réussi » ni « vide ».
    annoncerErreur('Comptages incomplets', `Non comptées : ${illisibles.join(', ')}. Essai non concluant : la restauration n'est pas prouvée.`);
    return 1;
  }
  if (comparaison.verdict === 'suspect') {
    const vides = comparaison.lignes.filter((l) => l.statut === 'vide').map((l) => l.nom);
    annoncerErreur('Restauration à regarder', `Collections essentielles vides dans la base restaurée alors qu'elles ne le sont pas en ligne : ${vides.join(', ')}.`);
    return 1;
  }
  if (comparaison.verdict === 'inconcluant') {
    annoncerAvertissement('Essai non concluant', 'Aucun document ni dans la base restaurée ni en ligne : rien n\'est prouvé.');
    return 1;
  }
  const recentes = comparaison.lignes.filter((l) => l.statut === 'vide-recente').map((l) => l.nom);
  if (recentes.length > 0) {
    annoncerNotice('Collections vides après restauration', `${recentes.join(', ')} : vides dans la restauration, pleines en ligne. Normal si elles sont nées après la sauvegarde ; à vérifier sinon.`);
  }
  annoncerNotice(
    'Restauration réussie',
    `${comparaison.totalRestauree} documents restaurés (${comparaison.lignes.length} collections) à partir de la sauvegarde du ${sauvegarde.snapshotTime} ; ` +
      `${comparaison.totalEnLigne} en ligne aujourd'hui. La base d'essai ${idBase} est supprimée à l'étape suivante.`,
  );
  return 0;
}

async function commandeNettoyer({ fetcher, jeton, env, pause }) {
  let idBase;
  try {
    idBase = baseCible(env).id;
  } catch (e) {
    annoncerErreur('Nettoyage impossible', e.message);
    return 1;
  }
  const resultat = await supprimerBaseEssai(fetcher, jeton, idBase, pause);
  if (resultat.erreur) {
    annoncerErreur('Base d\'essai non supprimée', `${resultat.erreur} ${AIDE_SUPPRESSION(idBase)}`);
    return 1;
  }
  console.log(resultat.dejaAbsente ? `La base ${idBase} n'existe pas (rien à supprimer).` : `La base ${idBase} est supprimée.`);
  return 0;
}

async function commandeLister({ fetcher, jeton }) {
  const r = await appeler(fetcher, jeton, 'GET', `${FIRESTORE}/projects/${PROJET}/databases`);
  if (!r.ok) {
    annoncerErreur('Bases illisibles', `Lecture des bases impossible (HTTP ${r.statut}) : ${detail(r)}`);
    return 1;
  }
  const bases = (Array.isArray(r.json?.databases) ? r.json.databases : []).map((b) => String(b.name ?? '').split('/').pop());
  console.log(`Bases du projet : ${bases.join(', ') || 'aucune'}.`);
  const restes = bases.filter((id) => id.startsWith(PREFIXE_BASE_ESSAI));
  if (restes.length > 0) {
    annoncerAvertissement('Bases d\'essai restées en place', `${restes.join(', ')}. ${AIDE_SUPPRESSION(restes[0])}`);
  }
  return 0;
}

export async function principal(argv, { fetcher = fetch, env = process.env, pause, lireRegles, renouveler } = {}) {
  const commandes = { essai: commandeEssai, nettoyer: commandeNettoyer, lister: commandeLister };
  const commande = commandes[argv[0]];
  if (!commande) {
    console.error('Usage : node securite/restauration.mjs essai | nettoyer | lister');
    return 2;
  }
  const jeton = env.JETON_GOOGLE;
  if (!jeton) {
    console.error('Jeton Google absent (variable JETON_GOOGLE).');
    return 2;
  }
  return commande({
    fetcher: renouveler ? fetcherRenouvelable(fetcher, renouveler) : fetcher,
    jeton,
    env,
    pause: pause ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms))),
    lireRegles: lireRegles ?? (() => readFileSync(path.join(DOSSIER_SECURITE, '..', 'firestore.rules'), 'utf8')),
    ecrireResume: (texte) => {
      if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, texte);
    },
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  principal(process.argv.slice(2), { renouveler: renouvelerParGcloud }).then((code) => process.exit(code));
}
