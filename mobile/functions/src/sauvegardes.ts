import { applicationDefault } from 'firebase-admin/app';
import type { Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { LIENS, pousser, type EnvoiPush, type Messagerie } from './notifications';

/**
 * Contrôle quotidien des sauvegardes de Firestore, fait par Google lui-même
 * (fonction planifiée) : il ne dépend ni de GitHub ni de la CI.
 *
 * Les sauvegardes sont prises par la planification gérée de Firestore (une
 * par jour, gardée 14 jours ; une par semaine, gardée 14 semaines). Cette
 * fonction ne fait que LIRE : elle vérifie que les deux planifications
 * existent et que la dernière sauvegarde a moins de 36 h, puis prévient les
 * comptes Admin par notification si ce n'est pas le cas. Une fois par
 * semaine elle dit aussi que tout va bien : sans ce petit signe, un silence
 * pourrait vouloir dire que le contrôle lui-même ne tourne plus.
 *
 * Droits du compte qui exécute les fonctions (lecture seule) :
 * `roles/datastore.backupsViewer` et `roles/datastore.backupSchedulesViewer`
 * (voir FIREBASE_SETUP.md, section 10.4). Ni créer, ni supprimer, ni
 * restaurer une sauvegarde ne passe par ici ; sans ces rôles, le contrôle
 * le dit (« illisible ») au lieu de laisser croire que tout va bien.
 */

export const PROJET = 'sprint-vtc';
const FIRESTORE = 'https://firestore.googleapis.com/v1';

/** Plus ancien âge accepté pour la dernière sauvegarde : 24 h de planification + 12 h de marge. */
export const DELAI_MAX_HEURES = 36;

/** Dimanche (`getUTCDay`) : jour du « tout va bien » hebdomadaire. */
export const JOUR_BILAN = 0;

// ---------------------------------------------------------------------
// Lecture de ce que Google répond
// ---------------------------------------------------------------------

type Objet = Record<string, unknown>;
const objet = (valeur: unknown): Objet => (typeof valeur === 'object' && valeur !== null ? (valeur as Objet) : {});
const liste = <T>(valeur: unknown): T[] => (Array.isArray(valeur) ? (valeur as T[]) : []);

export interface Planification {
  createTime?: string;
  dailyRecurrence?: unknown;
  weeklyRecurrence?: unknown;
}

export interface Sauvegarde {
  database?: string;
  snapshotTime?: string;
  expireTime?: string;
  state?: string;
}

export type TypePlanification = 'quotidienne' | 'hebdomadaire';
const PLANIFICATIONS_VOULUES: TypePlanification[] = ['quotidienne', 'hebdomadaire'];

/** « quotidienne », « hebdomadaire », ou null si la planification est d'un autre genre. */
export function typeDePlanification(planification: unknown): TypePlanification | null {
  if (typeof planification === 'object' && planification !== null) {
    if ('dailyRecurrence' in planification) return 'quotidienne';
    if ('weeklyRecurrence' in planification) return 'hebdomadaire';
  }
  return null;
}

/** Planifications voulues qui n'existent pas. */
export function planificationsAbsentes(existantes: Planification[]): TypePlanification[] {
  const presentes = new Set(existantes.map(typeDePlanification));
  return PLANIFICATIONS_VOULUES.filter((type) => !presentes.has(type));
}

/** Sauvegardes prêtes de cette base, la plus récente d'abord. */
export function sauvegardesPretes(sauvegardes: Sauvegarde[], baseDeDonnees: string): Sauvegarde[] {
  const quand = (s: Sauvegarde) => Date.parse(s.snapshotTime ?? '') || 0;
  return sauvegardes
    .filter((s) => s?.database === baseDeDonnees && s.state !== 'CREATING' && s.state !== 'NOT_AVAILABLE')
    .sort((a, b) => quand(b) - quand(a));
}

/** « 5 h », « 1 j 4 h » : un âge lisible. */
export function formaterAge(heures: number): string {
  const h = Math.max(0, Math.round(heures));
  return h < 24 ? `${h} h` : `${Math.floor(h / 24)} j ${h % 24} h`;
}

// ---------------------------------------------------------------------
// Verdict
// ---------------------------------------------------------------------

/**
 * - `ok` : la dernière sauvegarde a moins de 36 h ;
 * - `attente` : aucune pour l'instant, mais les planifications viennent d'être créées (moins de 36 h) ;
 * - `perimee` : la dernière date de plus de 36 h ;
 * - `absente` : aucune, alors que les planifications existent depuis plus de 36 h ;
 * - `planification-absente` : une des deux planifications n'existe pas ;
 * - `illisible` : Google n'a pas répondu ou a refusé la lecture (rôles manquants...).
 */
export type StatutControle = 'ok' | 'attente' | 'perimee' | 'absente' | 'planification-absente' | 'illisible';

export interface Verdict {
  statut: StatutControle;
  message: string;
  ageHeures?: number;
}

const heuresEntre = (debut: Date, fin: Date) => (fin.getTime() - debut.getTime()) / 3_600_000;

export function evaluerFraicheur(entree: {
  planifications: Planification[];
  sauvegardes: Sauvegarde[];
  maintenant: Date;
}): Verdict {
  const { planifications, sauvegardes, maintenant } = entree;
  const manquantes = planificationsAbsentes(planifications);
  if (manquantes.length > 0) {
    return { statut: 'planification-absente', message: `Planification absente : ${manquantes.join(', ')}.` };
  }
  const derniere = sauvegardes[0];
  if (!derniere) {
    const creations = planifications.map((p) => Date.parse(p.createTime ?? '')).filter((t) => !Number.isNaN(t));
    const plusAncienne = creations.length > 0 ? new Date(Math.min(...creations)) : null;
    if (plusAncienne && heuresEntre(plusAncienne, maintenant) <= DELAI_MAX_HEURES) {
      return {
        statut: 'attente',
        message: `Planifications créées il y a moins de ${DELAI_MAX_HEURES} h : la première sauvegarde est attendue dans les 24 h.`,
      };
    }
    return { statut: 'absente', message: `Aucune sauvegarde alors que les planifications existent depuis plus de ${DELAI_MAX_HEURES} h.` };
  }
  const instantane = new Date(derniere.snapshotTime ?? '');
  const ageHeures = Number.isNaN(instantane.getTime()) ? Number.POSITIVE_INFINITY : heuresEntre(instantane, maintenant);
  if (ageHeures <= DELAI_MAX_HEURES) {
    return { statut: 'ok', ageHeures, message: `Dernière sauvegarde il y a ${formaterAge(ageHeures)}.` };
  }
  return {
    statut: 'perimee',
    ageHeures,
    message: Number.isFinite(ageHeures)
      ? `La dernière sauvegarde a ${formaterAge(ageHeures)} : trop ancienne (plus de ${DELAI_MAX_HEURES} h).`
      : 'La date de la dernière sauvegarde est illisible.',
  };
}

// ---------------------------------------------------------------------
// Accès à Google (lecture seule)
// ---------------------------------------------------------------------

export interface ReponseGoogle {
  /** 0 : pas de réponse (réseau, jeton). */
  statut: number;
  json: unknown;
  texte: string;
}

export interface AccesGoogle {
  /** GET d'une API Google ; ne lève jamais pour un code HTTP d'erreur. */
  lire(url: string): Promise<ReponseGoogle>;
}

const ESSAIS = 3;
const DELAI_REPONSE_MS = 20_000;

function lireJson(texte: string): unknown {
  try {
    return texte ? JSON.parse(texte) : null;
  } catch {
    return null;
  }
}

/**
 * Appels réels : jeton du compte qui exécute la fonction (identifiants par
 * défaut de Google), trois essais en cas de panne passagère (réseau, 429, 5xx).
 * Le jeton n'est jamais recopié dans ce qui est rendu ni journalisé.
 */
export class AccesGoogleReel implements AccesGoogle {
  constructor(
    private readonly jeton: () => Promise<string> = async () => (await applicationDefault().getAccessToken()).access_token,
    private readonly fetcher: typeof fetch = fetch,
    private readonly pause: (ms: number) => Promise<void> = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  ) {}

  async lire(url: string): Promise<ReponseGoogle> {
    let derniere: ReponseGoogle = { statut: 0, json: null, texte: '' };
    for (let essai = 1; essai <= ESSAIS; essai++) {
      if (essai > 1) await this.pause(1000 * 2 ** (essai - 2));
      let jeton: string;
      try {
        jeton = await this.jeton();
      } catch (e) {
        derniere = { statut: 0, json: null, texte: `Jeton Google indisponible : ${(e as Error).message}` };
        continue;
      }
      try {
        const reponse = await this.fetcher(url, {
          headers: { authorization: `Bearer ${jeton}` },
          signal: AbortSignal.timeout(DELAI_REPONSE_MS),
        });
        const texte = await reponse.text();
        derniere = { statut: reponse.status, json: lireJson(texte), texte };
        // 429 et 5xx : panne passagère possible, on réessaie ; tout le reste est définitif.
        if (reponse.status !== 429 && reponse.status < 500) return derniere;
      } catch (e) {
        derniere = { statut: 0, json: null, texte: `Google injoignable : ${(e as Error).message}` };
      }
    }
    return derniere;
  }
}

function detail(r: ReponseGoogle): string {
  const message = objet(objet(r.json).error).message;
  return typeof message === 'string' && message ? message : r.texte.slice(0, 200);
}

function illisible(quoi: string, r: ReponseGoogle): Verdict {
  const http = r.statut > 0 ? ` (HTTP ${r.statut})` : '';
  return { statut: 'illisible', message: `Lecture des ${quoi} impossible${http} : ${detail(r)}` };
}

/** Lit les planifications et les sauvegardes de la base, et rend le verdict. */
export async function controlerSauvegardes(google: AccesGoogle, maintenant: Date, projet: string = PROJET): Promise<Verdict> {
  const base = `projects/${projet}/databases/(default)`;

  const lues = await google.lire(`${FIRESTORE}/${base}/backupSchedules`);
  if (lues.statut !== 200) return illisible('planifications', lues);
  const planifications = liste<Planification>(objet(lues.json).backupSchedules);

  // Emplacement de la base ; à défaut (lecture refusée), tous les emplacements (« - »).
  const infos = await google.lire(`${FIRESTORE}/${base}`);
  const emplacement = objet(infos.json).locationId;
  const lieu = infos.statut === 200 && typeof emplacement === 'string' && emplacement ? emplacement : '-';

  const copies = await google.lire(`${FIRESTORE}/projects/${projet}/locations/${lieu}/backups`);
  if (copies.statut !== 200) return illisible('sauvegardes', copies);
  const injoignables = liste<string>(objet(copies.json).unreachable);
  if (injoignables.length > 0) {
    logger.warn('Sauvegardes Firestore : emplacement injoignable', { injoignables });
  }
  const sauvegardes = sauvegardesPretes(liste<Sauvegarde>(objet(copies.json).backups), base);
  return evaluerFraicheur({ planifications, sauvegardes, maintenant });
}

// ---------------------------------------------------------------------
// Prévenir les Admin
// ---------------------------------------------------------------------

/** Notification d'alerte : ce qui ne va pas, et où regarder. */
export function alerte(verdict: Verdict): EnvoiPush {
  return {
    titre: 'Sauvegardes : à vérifier',
    corps: `${verdict.message} Voir Google Cloud > Firestore > Sauvegardes.`,
    canal: 'messages',
    lien: LIENS.admin,
    donnees: { type: 'sauvegardes', statut: verdict.statut },
    dureeVieSecondes: 24 * 3600,
  };
}

/** Le « tout va bien » du dimanche : la preuve que le contrôle tourne encore. */
export function bilanHebdomadaire(verdict: Verdict): EnvoiPush {
  return {
    titre: 'Sauvegardes : tout va bien',
    corps: `${verdict.message} Contrôle automatique chaque jour.`,
    canal: 'messages',
    lien: LIENS.admin,
    donnees: { type: 'sauvegardes', statut: 'ok' },
    dureeVieSecondes: 12 * 3600,
  };
}

/** Envoie [push] aux appareils de tous les comptes Admin ; rend le nombre de téléphones atteints. */
export async function prevenirAdmins(db: Firestore, messagerie: Messagerie | undefined, push: EnvoiPush): Promise<number> {
  const admins = await db.collection('users').where('role', '==', 'admin').get();
  return pousser(
    db,
    messagerie,
    admins.docs.map((doc) => doc.id),
    push,
  );
}

export interface Dependances {
  google: AccesGoogle;
  /** Prévient les Admin ; rend le nombre de téléphones atteints. */
  prevenir: (push: EnvoiPush) => Promise<number>;
  maintenant: Date;
}

/**
 * Le contrôle complet : verdict, journal, et notification aux Admin si ça ne
 * va pas (tous les jours tant que ça dure) ou, un dimanche, pour dire que
 * tout va bien.
 */
export async function verifierSauvegardes(dep: Dependances): Promise<Verdict> {
  const verdict = await controlerSauvegardes(dep.google, dep.maintenant);
  if (verdict.statut === 'ok') {
    logger.info(`Sauvegardes Firestore : ${verdict.message}`);
    if (dep.maintenant.getUTCDay() === JOUR_BILAN) {
      const remis = await dep.prevenir(bilanHebdomadaire(verdict));
      logger.info('Sauvegardes Firestore : bilan hebdomadaire envoyé', { appareils: remis });
    }
  } else if (verdict.statut === 'attente') {
    logger.info(`Sauvegardes Firestore : ${verdict.message}`);
  } else {
    logger.error(`Sauvegardes Firestore à vérifier : ${verdict.message}`, { statut: verdict.statut });
    const remis = await dep.prevenir(alerte(verdict));
    if (remis === 0) {
      logger.error("Alerte des sauvegardes non remise : aucun appareil Admin n'a les notifications actives.");
    }
  }
  return verdict;
}
