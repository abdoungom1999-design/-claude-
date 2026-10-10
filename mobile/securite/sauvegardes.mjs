#!/usr/bin/env node
// Sauvegardes automatiques de la base Firestore.
//
//   node securite/sauvegardes.mjs droits      le compte de déploiement a-t-il les droits nécessaires ?
//   node securite/sauvegardes.mjs planifier   crée les planifications manquantes (n'en modifie aucune)
//   node securite/sauvegardes.mjs verifier    une sauvegarde récente existe-t-elle réellement ?
//   node securite/sauvegardes.mjs diagnostic  (lecture seule) quel compte exécute les fonctions, et quels droits manquent
//                                             pour le contrôle par fonction planifiée et pour l'essai de restauration ?
//
// Les sauvegardes sont prises par Google (planification gérée de Firestore),
// pas par GitHub : une par jour, gardée 14 jours, et une par semaine (le
// dimanche), gardée 14 semaines, à l'heure que Google choisit (UTC). Elles
// continuent donc même si GitHub ne tourne plus ; la CI ne fait que les
// mettre en place et surveiller qu'elles existent bien. Une sauvegarde
// contient les documents et les index, pas les règles de sécurité (dans le
// dépôt) ni les politiques de durée de vie. Elle ne couvre ni les comptes de
// connexion (Firebase Auth) ni les fichiers (Storage).
//
// Le jeton Google vient de la variable JETON_GOOGLE (gcloud auth print-access-token) ;
// il n'est jamais affiché. Code 0 : tout va bien (ou la première sauvegarde est
// attendue) ; 1 : à corriger ; 2 : jeton absent ou commande inconnue.
import { appendFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { annoncerAvertissement, annoncerErreur, annoncerNotice } from './commun.mjs';

export const PROJET = 'sprint-vtc';
export const BASE_DE_DONNEES = `projects/${PROJET}/databases/(default)`;
const FIRESTORE = 'https://firestore.googleapis.com/v1';
const GESTIONNAIRE = 'https://cloudresourcemanager.googleapis.com/v1';

const JOUR = 24 * 3600;

/** Les deux planifications voulues (Firestore n'en admet pas plus : une par jour, une par semaine). */
export const PLANIFICATIONS = [
  {
    type: 'quotidienne',
    libelle: 'une par jour, gardée 14 jours',
    retentionSecondes: 14 * JOUR,
    recurrence: { dailyRecurrence: {} },
  },
  {
    type: 'hebdomadaire',
    libelle: 'une par semaine (le dimanche), gardée 14 semaines',
    retentionSecondes: 14 * 7 * JOUR,
    recurrence: { weeklyRecurrence: { day: 'SUNDAY' } },
  },
];

/** Droits Google nécessaires pour créer les planifications et lire les sauvegardes. */
export const DROITS_REQUIS = [
  'datastore.backupSchedules.create',
  'datastore.backupSchedules.list',
  'datastore.backupSchedules.get',
  'datastore.backups.list',
  'datastore.backups.get',
];

/** Plus ancien âge accepté pour la dernière sauvegarde : 24 h de planification + 12 h de marge. */
export const DELAI_MAX_HEURES = 36;

/** « quotidienne », « hebdomadaire », ou null si la planification est d'un autre genre. */
export function typeDePlanification(planification) {
  if (planification && typeof planification === 'object') {
    if ('dailyRecurrence' in planification) return 'quotidienne';
    if ('weeklyRecurrence' in planification) return 'hebdomadaire';
  }
  return null;
}

/** « 1209600s » devient 1209600 ; NaN si le format est inattendu. */
export function retentionEnSecondes(texte) {
  const m = /^(\d+(?:\.\d+)?)s$/.exec(String(texte ?? ''));
  return m ? Number(m[1]) : Number.NaN;
}

/** Planifications voulues qui n'existent pas encore. */
export function planificationsACreer(existantes) {
  const presentes = new Set(existantes.map(typeDePlanification));
  return PLANIFICATIONS.filter((p) => !presentes.has(p.type));
}

/** Planifications existantes dont la durée de conservation n'est pas celle voulue (à signaler, jamais modifiées). */
export function ecartsDeRetention(existantes) {
  const ecarts = [];
  for (const voulue of PLANIFICATIONS) {
    const trouvee = existantes.find((p) => typeDePlanification(p) === voulue.type);
    if (!trouvee) continue;
    const actuelle = retentionEnSecondes(trouvee.retention);
    if (actuelle !== voulue.retentionSecondes) ecarts.push({ type: voulue.type, actuelle: trouvee.retention, voulue: `${voulue.retentionSecondes}s` });
  }
  return ecarts;
}

/** Sauvegardes prêtes de la base, la plus récente d'abord. */
export function sauvegardesDeLaBase(sauvegardes) {
  return sauvegardes
    .filter((s) => s?.database === BASE_DE_DONNEES && s.state !== 'CREATING' && s.state !== 'NOT_AVAILABLE')
    .sort((a, b) => new Date(b.snapshotTime).getTime() - new Date(a.snapshotTime).getTime());
}

const heuresEntre = (debut, fin) => (fin.getTime() - debut.getTime()) / 3_600_000;

/** « 5 h », « 1 j 4 h » : un âge lisible. */
export function formaterAge(heures) {
  const h = Math.max(0, Math.round(heures));
  return h < 24 ? `${h} h` : `${Math.floor(h / 24)} j ${h % 24} h`;
}

/**
 * Verdict sur les sauvegardes :
 * - `ok` : la dernière a moins de 36 h ;
 * - `attente` : aucune pour l'instant, mais les planifications viennent d'être créées (moins de 36 h) ;
 * - `perimee` : la dernière date de plus de 36 h ;
 * - `absente` : aucune, alors que les planifications existent depuis plus de 36 h ;
 * - `planification-absente` : une des deux planifications n'existe pas.
 */
export function evaluerFraicheur({ planifications, sauvegardes, maintenant = new Date(), delaiMaxHeures = DELAI_MAX_HEURES }) {
  const manquantes = planificationsACreer(planifications);
  if (manquantes.length > 0) {
    return {
      statut: 'planification-absente',
      manquantes: manquantes.map((p) => p.type),
      message: `Planification absente : ${manquantes.map((p) => p.type).join(', ')}.`,
    };
  }
  const derniere = sauvegardes[0] ?? null;
  if (!derniere) {
    const creations = planifications.map((p) => new Date(p.createTime).getTime()).filter((t) => !Number.isNaN(t));
    const plusAncienne = creations.length > 0 ? new Date(Math.min(...creations)) : null;
    if (plusAncienne && heuresEntre(plusAncienne, maintenant) <= delaiMaxHeures) {
      return {
        statut: 'attente',
        message: `Planifications créées il y a moins de ${delaiMaxHeures} h : la première sauvegarde est attendue dans les 24 h.`,
      };
    }
    return { statut: 'absente', message: `Aucune sauvegarde alors que les planifications existent depuis plus de ${delaiMaxHeures} h.` };
  }
  const instantane = new Date(derniere.snapshotTime);
  const ageHeures = Number.isNaN(instantane.getTime()) ? Number.POSITIVE_INFINITY : heuresEntre(instantane, maintenant);
  if (ageHeures <= delaiMaxHeures) {
    return { statut: 'ok', derniere, ageHeures, message: `Dernière sauvegarde il y a ${formaterAge(ageHeures)}.` };
  }
  const message = Number.isFinite(ageHeures)
    ? `La dernière sauvegarde a ${formaterAge(ageHeures)} : trop ancienne (plus de ${delaiMaxHeures} h).`
    : 'La date de la dernière sauvegarde est illisible.';
  return { statut: 'perimee', derniere, ageHeures, message };
}

/** Entier d'une réponse JSON de Google (les int64 arrivent en texte) ; null s'il est absent ou illisible. */
const entierGoogle = (valeur) => {
  if (typeof valeur === 'number' && Number.isFinite(valeur) && valeur >= 0) return valeur;
  if (typeof valeur === 'string' && /^\d+$/.test(valeur)) return Number(valeur);
  return null;
};

/**
 * Taille (« 2.5 Mo ») et nombre de documents d'une sauvegarde, ou null pour
 * chacun tant que Google ne les donne pas : le champ `stats` reste vide jusqu'à
 * ce que la sauvegarde soit entièrement copiée sur son stockage secondaire
 * (documentation de l'API Firestore Admin). Une sauvegarde prête sans `stats`
 * existe bel et bien, mais son contenu n'est pas chiffré : jamais « NaN ».
 */
export function statistiquesDe(sauvegarde) {
  const octets = entierGoogle(sauvegarde?.stats?.sizeBytes);
  return {
    taille: octets === null ? null : `${(octets / 1_000_000).toFixed(1)} Mo`,
    documents: entierGoogle(sauvegarde?.stats?.documentCount),
  };
}

/** « 2.5 Mo  1234 documents », ou la mention que Google ne les a pas encore communiqués. */
export function decrireStatistiques(sauvegarde) {
  const { taille, documents } = statistiquesDe(sauvegarde);
  if (taille === null && documents === null) return 'taille et nombre de documents non communiqués par Google';
  return `${taille ?? 'taille inconnue'}  ${documents ?? '?'} documents`;
}

/** Résumé en Markdown pour la page du run (GITHUB_STEP_SUMMARY). */
export function resumeMarkdown({ planifications, sauvegardes, evaluation, emplacement }) {
  const verdict = { ok: 'OK', attente: 'EN ATTENTE', perimee: 'PROBLÈME', absente: 'PROBLÈME', 'planification-absente': 'PROBLÈME' }[evaluation.statut];
  const lignes = [`## Sauvegardes de la base Firestore · ${verdict}`, '', evaluation.message, ''];
  lignes.push('**Planifications** (gérées par Google, heure UTC) :', '');
  for (const voulue of PLANIFICATIONS) {
    const existante = planifications.find((p) => typeDePlanification(p) === voulue.type);
    lignes.push(`- ${voulue.type} : ${existante ? `en place (${voulue.libelle})` : 'ABSENTE'}`);
  }
  lignes.push('', `**Dernières sauvegardes** (emplacement ${emplacement}) :`, '');
  if (sauvegardes.length === 0) {
    lignes.push('Aucune pour le moment.');
  } else {
    lignes.push('| Instantané (UTC) | Conservée jusqu\'au | Taille | Documents |', '|---|---|---|---|');
    for (const s of sauvegardes.slice(0, 5)) {
      const { taille, documents } = statistiquesDe(s);
      lignes.push(`| ${s.snapshotTime} | ${s.expireTime ?? '?'} | ${taille ?? 'non communiquée'} | ${documents ?? 'non communiqué'} |`);
    }
    if (sauvegardes.slice(0, 5).some((s) => statistiquesDe(s).taille === null)) {
      lignes.push('', 'Taille et nombre de documents : Google ne les renseigne qu\'une fois la sauvegarde entièrement copiée.');
    }
  }
  return `${lignes.join('\n')}\n`;
}

/** Appel d'une API Google ; ne lève jamais pour un code HTTP d'erreur. */
export async function appeler(fetcher, jeton, methode, url, corps) {
  const reponse = await fetcher(url, {
    method: methode,
    headers: { authorization: `Bearer ${jeton}`, ...(corps === undefined ? {} : { 'content-type': 'application/json' }) },
    body: corps === undefined ? undefined : JSON.stringify(corps),
    signal: AbortSignal.timeout(30000),
  });
  const texte = await reponse.text();
  let json = null;
  try {
    json = texte ? JSON.parse(texte) : null;
  } catch {
    // Corps qui n'est pas du JSON : on garde le texte.
  }
  return { statut: reponse.status, ok: reponse.ok, json, texte };
}

const detail = (r) => r.json?.error?.message ?? String(r.texte ?? '').slice(0, 200);

/** Droits du compte de déploiement : la liste de ceux qui manquent, ou une erreur de vérification. */
export async function verifierDroits(fetcher, jeton) {
  const r = await appeler(fetcher, jeton, 'POST', `${GESTIONNAIRE}/projects/${PROJET}:testIamPermissions`, {
    permissions: DROITS_REQUIS,
  });
  if (!r.ok) return { erreur: `Google a refusé la vérification des droits (HTTP ${r.statut}) : ${detail(r)}` };
  const accordes = new Set(r.json?.permissions ?? []);
  return { manquants: DROITS_REQUIS.filter((d) => !accordes.has(d)) };
}

export async function lirePlanifications(fetcher, jeton) {
  const r = await appeler(fetcher, jeton, 'GET', `${FIRESTORE}/${BASE_DE_DONNEES}/backupSchedules`);
  if (!r.ok) return { erreur: `Lecture des planifications impossible (HTTP ${r.statut}) : ${detail(r)}` };
  return { planifications: Array.isArray(r.json?.backupSchedules) ? r.json.backupSchedules : [] };
}

export async function creerPlanification(fetcher, jeton, voulue) {
  const r = await appeler(fetcher, jeton, 'POST', `${FIRESTORE}/${BASE_DE_DONNEES}/backupSchedules`, {
    retention: `${voulue.retentionSecondes}s`,
    ...voulue.recurrence,
  });
  if (!r.ok) return { erreur: `Création de la planification ${voulue.type} impossible (HTTP ${r.statut}) : ${detail(r)}` };
  return { planification: r.json };
}

/** Sauvegardes de la base, dans l'emplacement de celle-ci (ou tous les emplacements si on ne le connaît pas). */
export async function lireSauvegardes(fetcher, jeton) {
  const base = await appeler(fetcher, jeton, 'GET', `${FIRESTORE}/${BASE_DE_DONNEES}`);
  const emplacement = base.ok && typeof base.json?.locationId === 'string' && base.json.locationId ? base.json.locationId : '-';
  const r = await appeler(fetcher, jeton, 'GET', `${FIRESTORE}/projects/${PROJET}/locations/${emplacement}/backups`);
  if (!r.ok) return { erreur: `Lecture des sauvegardes impossible (HTTP ${r.statut}) : ${detail(r)}` };
  return {
    emplacement,
    sauvegardes: sauvegardesDeLaBase(Array.isArray(r.json?.backups) ? r.json.backups : []),
    injoignables: Array.isArray(r.json?.unreachable) ? r.json.unreachable : [],
  };
}

/** Rôles que le compte qui exécute les Cloud Functions doit avoir pour que la fonction de contrôle lise les sauvegardes. */
export const ROLES_FONCTION = ['roles/datastore.backupsViewer', 'roles/datastore.backupSchedulesViewer'];

/** Droits du compte de déploiement pour l'essai de restauration : permission Google, et à quoi elle sert. */
export const DROITS_RESTAURATION = [
  ['datastore.backups.restoreDatabase', 'restaurer une sauvegarde dans une nouvelle base'],
  ['datastore.databases.create', 'créer la base d\'essai'],
  ['datastore.databases.getMetadata', 'lire l\'état d\'une base'],
  ['datastore.databases.list', 'lister les bases'],
  ['datastore.operations.get', 'suivre la restauration en cours'],
  ['datastore.operations.list', 'lister les opérations en cours'],
  ['datastore.entities.get', 'lire des documents pour la comparaison'],
  ['datastore.entities.list', 'lister les collections et les documents'],
  ['datastore.databases.delete', 'supprimer la base d\'essai'],
];

const CLOUD_RUN = 'https://run.googleapis.com/v2';
const REGION_FONCTIONS = 'europe-west1';
/** Fonction déjà en ligne dont on lit le compte d'exécution (service Cloud Run, nom en minuscules). */
const FONCTION_TEMOIN = 'surveillercommandes';

/** Une permission à la fois : une permission inconnue de Google ferait refuser toute la demande. */
export async function testerDroit(fetcher, jeton, droit) {
  const r = await appeler(fetcher, jeton, 'POST', `${GESTIONNAIRE}/projects/${PROJET}:testIamPermissions`, { permissions: [droit] });
  if (!r.ok) return { droit, etat: 'inconnu', detail: `HTTP ${r.statut} : ${detail(r)}` };
  return { droit, etat: (r.json?.permissions ?? []).includes(droit) ? 'accordé' : 'manquant' };
}

/** Compte qui exécute les Cloud Functions, lu sur une fonction déjà déployée. */
export async function lireCompteDesFonctions(fetcher, jeton) {
  const r = await appeler(fetcher, jeton, 'GET', `${CLOUD_RUN}/projects/${PROJET}/locations/${REGION_FONCTIONS}/services/${FONCTION_TEMOIN}`);
  if (!r.ok) return { erreur: `Lecture de la fonction ${FONCTION_TEMOIN} impossible (HTTP ${r.statut}) : ${detail(r)}` };
  const compte = r.json?.template?.serviceAccount;
  return typeof compte === 'string' && compte ? { compte } : { erreur: `Google ne nomme pas le compte d'exécution de ${FONCTION_TEMOIN}.` };
}

/** Rôles que ce compte de service a directement sur le projet (liés sans condition). */
export async function lireRolesDuCompte(fetcher, jeton, compte) {
  const r = await appeler(fetcher, jeton, 'POST', `${GESTIONNAIRE}/projects/${PROJET}:getIamPolicy`, {
    options: { requestedPolicyVersion: 3 },
  });
  if (!r.ok) return { erreur: `Lecture des rôles du projet impossible (HTTP ${r.statut}) : ${detail(r)}` };
  const membre = `serviceAccount:${compte}`;
  const roles = (Array.isArray(r.json?.bindings) ? r.json.bindings : [])
    .filter((liaison) => !liaison.condition && Array.isArray(liaison.members) && liaison.members.includes(membre))
    .map((liaison) => liaison.role)
    .sort();
  return { roles };
}

const AIDE_DROITS =
  'Dans Google Cloud > IAM, ajoutez au compte « github-deploy » les rôles « roles/datastore.backupSchedulesAdmin » et ' +
  '« roles/datastore.backupsViewer » (voir mobile/FIREBASE_SETUP.md, section 10), puis relancez ce contrôle.';

async function commandeDroits({ fetcher, jeton }) {
  const bilan = await verifierDroits(fetcher, jeton);
  if (bilan.erreur) {
    annoncerErreur('Vérification des droits impossible', bilan.erreur);
    return 1;
  }
  if (bilan.manquants.length > 0) {
    console.log(`Droits manquants : ${bilan.manquants.join(', ')}`);
    annoncerErreur('Droits manquants pour les sauvegardes', `Le compte de déploiement n'a pas : ${bilan.manquants.join(', ')}. ${AIDE_DROITS}`);
    return 1;
  }
  console.log(`Droits de sauvegarde : ${DROITS_REQUIS.length}/${DROITS_REQUIS.length} accordés.`);
  return 0;
}

async function commandePlanifier({ fetcher, jeton }) {
  const lecture = await lirePlanifications(fetcher, jeton);
  if (lecture.erreur) {
    annoncerErreur('Planifications illisibles', `${lecture.erreur}. ${AIDE_DROITS}`);
    return 1;
  }
  for (const ecart of ecartsDeRetention(lecture.planifications)) {
    annoncerAvertissement(
      'Durée de conservation différente',
      `La planification ${ecart.type} garde ses sauvegardes ${ecart.actuelle} au lieu de ${ecart.voulue} : laissée telle quelle.`,
    );
  }
  const aCreer = planificationsACreer(lecture.planifications);
  for (const voulue of PLANIFICATIONS.filter((p) => !aCreer.includes(p))) console.log(`Déjà en place : ${voulue.type} (${voulue.libelle}).`);
  for (const voulue of aCreer) {
    const creation = await creerPlanification(fetcher, jeton, voulue);
    if (creation.erreur) {
      annoncerErreur('Planification non créée', `${creation.erreur}. ${AIDE_DROITS}`);
      return 1;
    }
    console.log(`Créée : ${voulue.type} (${voulue.libelle}).`);
  }
  return 0;
}

async function commandeVerifier({ fetcher, jeton, maintenant, ecrireResume }) {
  const lecture = await lirePlanifications(fetcher, jeton);
  if (lecture.erreur) {
    annoncerErreur('Planifications illisibles', `${lecture.erreur}. ${AIDE_DROITS}`);
    return 1;
  }
  const lues = await lireSauvegardes(fetcher, jeton);
  if (lues.erreur) {
    annoncerErreur('Sauvegardes illisibles', `${lues.erreur}. ${AIDE_DROITS}`);
    return 1;
  }
  if (lues.injoignables.length > 0) {
    annoncerAvertissement('Emplacement injoignable', `Google n'a pas pu lire les sauvegardes de : ${lues.injoignables.join(', ')}.`);
  }
  const evaluation = evaluerFraicheur({ planifications: lecture.planifications, sauvegardes: lues.sauvegardes, maintenant });
  ecrireResume(resumeMarkdown({ planifications: lecture.planifications, sauvegardes: lues.sauvegardes, evaluation, emplacement: lues.emplacement }));
  console.log(`Sauvegardes (${lues.emplacement}) : ${lues.sauvegardes.length} prête(s). ${evaluation.message}`);
  for (const s of lues.sauvegardes.slice(0, 3)) {
    console.log(`  ${s.snapshotTime}  ${decrireStatistiques(s)}  jusqu'au ${s.expireTime ?? '?'}`);
  }
  const derniere = lues.sauvegardes[0];
  if (derniere) {
    // Seulement les noms des champs : de quoi voir ce que Google renvoie vraiment, sans rien divulguer.
    console.log(`  Dernière : état ${derniere.state ?? '?'} ; champs reçus : ${Object.keys(derniere).sort().join(', ')}.`);
    const { taille, documents } = statistiquesDe(derniere);
    if (taille === null && documents === null) {
      annoncerNotice(
        'Taille de la sauvegarde non communiquée',
        'La sauvegarde existe et est prête, mais Google ne donne pas encore sa taille ni son nombre de documents ' +
          '(champ « stats » vide tant qu\'elle n\'est pas entièrement copiée). Seul un essai de restauration prouve son contenu.',
      );
    }
  }
  if (evaluation.statut === 'ok') return 0;
  if (evaluation.statut === 'attente') {
    annoncerNotice('Première sauvegarde attendue', evaluation.message);
    return 0;
  }
  annoncerErreur('Sauvegardes Firestore à vérifier', evaluation.message);
  return 1;
}

/**
 * Lecture seule : de quoi dire au propriétaire du projet, sans rien supposer, quels rôles
 * donner (contrôle par fonction planifiée) et quel droit temporaire accorder (essai de restauration).
 */
async function commandeDiagnostic({ fetcher, jeton }) {
  const resultat = { compte: null, rolesManquants: null, droitsManquants: [] };

  const fonctions = await lireCompteDesFonctions(fetcher, jeton);
  if (fonctions.erreur) {
    console.log(`Compte qui exécute les Cloud Functions : illisible. ${fonctions.erreur}`);
  } else {
    resultat.compte = fonctions.compte;
    console.log(`Compte qui exécute les Cloud Functions (lu sur « ${FONCTION_TEMOIN} », ${REGION_FONCTIONS}) : ${fonctions.compte}`);
    const roles = await lireRolesDuCompte(fetcher, jeton, fonctions.compte);
    if (roles.erreur) {
      console.log(`  Ses rôles sur le projet : illisibles. ${roles.erreur}`);
    } else {
      console.log(`  Ses rôles sur le projet : ${roles.roles.length > 0 ? roles.roles.join(', ') : 'aucun'}`);
      resultat.rolesManquants = ROLES_FONCTION.filter((role) => !roles.roles.includes(role));
      for (const role of ROLES_FONCTION) console.log(`  ${roles.roles.includes(role) ? 'présent ' : 'ABSENT  '} ${role}`);
    }
  }

  console.log("Droits du compte de déploiement pour l'essai de restauration :");
  for (const [droit, utilite] of DROITS_RESTAURATION) {
    const test = await testerDroit(fetcher, jeton, droit);
    if (test.etat !== 'accordé') resultat.droitsManquants.push(droit);
    console.log(`  ${test.etat.padEnd(8)} ${droit} (${utilite})${test.detail ? ` — ${test.detail}` : ''}`);
  }

  const morceaux = [
    `compte des fonctions : ${resultat.compte ?? 'illisible'}`,
    `rôles à donner à ce compte : ${resultat.rolesManquants === null ? 'non vérifiés' : resultat.rolesManquants.join(', ') || 'aucun'}`,
    `droits de restauration manquants au compte de déploiement : ${resultat.droitsManquants.join(', ') || 'aucun'}`,
  ];
  annoncerNotice('Diagnostic des droits (lecture seule)', morceaux.join(' ; '));
  return 0;
}

export async function principal(argv, { fetcher = fetch, env = process.env, maintenant = new Date() } = {}) {
  const commande = argv[0];
  const commandes = { droits: commandeDroits, planifier: commandePlanifier, verifier: commandeVerifier, diagnostic: commandeDiagnostic };
  if (!commandes[commande]) {
    console.error('Usage : node securite/sauvegardes.mjs droits | planifier | verifier | diagnostic');
    return 2;
  }
  const jeton = env.JETON_GOOGLE;
  if (!jeton) {
    console.error('Jeton Google absent (variable JETON_GOOGLE).');
    return 2;
  }
  const ecrireResume = (texte) => {
    if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, texte);
  };
  return commandes[commande]({ fetcher, jeton, maintenant, ecrireResume });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) principal(process.argv.slice(2)).then((code) => process.exit(code));
