import { logger } from 'firebase-functions';
import { Timestamp, type Firestore } from 'firebase-admin/firestore';
import { LIENS, type EnvoiPush } from './notifications';
import { STATUTS_COMMANDE } from './paiements';
import { STATUTS_RETRAIT } from './retraits';

/**
 * Observation (phase C de la sécurité).
 *
 * Ce module REGARDE ce qui se passe et le dit (journal du serveur, notification
 * aux Admin) : il ne refuse JAMAIS rien et ne change le résultat d'aucune
 * fonction. Tout y est protégé : une erreur d'observation est journalisée et
 * avalée, elle ne peut pas faire échouer un paiement, un retrait ou une
 * recherche d'adresse.
 *
 * Pourquoi observer avant de refuser : les seuils ci-dessous sont des valeurs
 * de départ, posées sans données réelles. Refuser un client légitime pour un
 * seuil mal réglé est pire que de laisser passer un abus. On observe donc ce que
 * font les vrais utilisateurs, on règle les seuils d'après le journal, puis le
 * client décide s'il veut les appliquer (refus), avec son feu vert.
 */

/** Au-delà de ce délai, la réponse d'une fonction n'attend plus l'observation. */
export const DELAI_OBSERVATION_MS = 4000;

/**
 * Attend [travail] au plus [delaiMs]. L'observation ne doit JAMAIS retarder la
 * réponse d'une fonction ni la faire échouer : un crédit de portefeuille déjà
 * enregistré dont la réponse tarderait (notification en panne) ferait croire à
 * un échec, et l'Admin le referait. Une observation trop lente continue sans
 * qu'on l'attende ; une observation en erreur est journalisée.
 */
export async function sansRetarder(travail: Promise<unknown>, delaiMs: number = DELAI_OBSERVATION_MS): Promise<void> {
  let minuteur: NodeJS.Timeout | undefined;
  try {
    await Promise.race([
      travail.then(
        () => undefined,
        (e) => logger.error('Observation en erreur', e),
      ),
      new Promise<void>((fini) => {
        minuteur = setTimeout(() => {
          logger.warn('Observation trop lente : la réponse est rendue sans l\'attendre');
          fini();
        }, delaiMs);
      }),
    ]);
  } finally {
    if (minuteur) clearTimeout(minuteur);
  }
}

/** Comptes gardés en mémoire par l'observateur de fréquence : au-delà, les appels trop anciens sont oubliés. */
const COMPTES_MEMORISES_MAX = 5000;

// ---------------------------------------------------------------------
// 1. Fréquence des appels par compte
// ---------------------------------------------------------------------

export interface RegleFrequence {
  fenetreSecondes: number;
  /** Nombre d'appels d'un même compte, dans la fenêtre, au-delà duquel on le signale. */
  seuil: number;
}

/**
 * Valeurs de départ : large au-dessus de l'usage normal d'une personne qui se
 * sert de l'app, bien en dessous de ce que fait un script. À régler d'après
 * le journal (« Observation : fréquence anormale »).
 */
export const REGLES_FREQUENCE: Readonly<Record<string, RegleFrequence>> = {
  creerPaiement: { fenetreSecondes: 60, seuil: 6 },
  creerRecharge: { fenetreSecondes: 60, seuil: 6 },
  demanderRetrait: { fenetreSecondes: 60, seuil: 5 },
  annulerCourse: { fenetreSecondes: 60, seuil: 6 },
  estimerPrix: { fenetreSecondes: 60, seuil: 30 },
  rechercherAdresses: { fenetreSecondes: 60, seuil: 90 },
  coordonneesAdresse: { fenetreSecondes: 60, seuil: 30 },
  itineraireCourse: { fenetreSecondes: 60, seuil: 20 },
  chauffeursProches: { fenetreSecondes: 60, seuil: 30 },
  notifierMessage: { fenetreSecondes: 60, seuil: 30 },
};

/** Les Admin ne sont prévenus qu'à ce multiple du seuil : un pic isolé ne dérange personne. */
export const MULTIPLE_ALERTE_ADMIN = 5;

/** Une alerte aux Admin, au plus, par compte et par fonction et par heure. */
const DELAI_ALERTE_ADMIN_MS = 60 * 60 * 1000;

export interface ActiviteAnormale {
  uid: string;
  fonction: string;
  appels: number;
  regle: RegleFrequence;
}

/**
 * Compte, par instance du serveur et en mémoire, les appels récents de chaque
 * compte à chaque fonction surveillée. Approximatif (chaque instance compte
 * pour elle-même), donc réservé à l'observation : il ne sert qu'à repérer un
 * script, pas à rationner un utilisateur.
 */
export class ObservateurFrequence {
  private readonly appels = new Map<string, number[]>();
  private readonly dernierJournal = new Map<string, number>();
  private readonly derniereAlerte = new Map<string, number>();

  constructor(
    /** Prévient les Admin d'une activité très anormale. Absent (tests) : personne n'est prévenu. */
    private readonly alerter?: (activite: ActiviteAnormale) => Promise<void>,
    private readonly maintenant: () => number = Date.now,
    private readonly regles: Readonly<Record<string, RegleFrequence>> = REGLES_FREQUENCE,
  ) {}

  /** Note un appel ; rend `true` si le compte dépasse le seuil de la fonction. Ne lève jamais d'erreur. */
  async observer(fonction: string, uid: string | undefined): Promise<boolean> {
    try {
      const regle = this.regles[fonction];
      if (!uid || !regle) return false;
      const maintenant = this.maintenant();
      const fenetreMs = regle.fenetreSecondes * 1000;
      const cle = `${fonction}|${uid}`;
      const recents = (this.appels.get(cle) ?? []).filter((t) => maintenant - t < fenetreMs);
      recents.push(maintenant);
      this.appels.set(cle, recents);
      if (this.appels.size > COMPTES_MEMORISES_MAX) this.nettoyer(maintenant);
      if (recents.length <= regle.seuil) return false;

      // Une ligne de journal par fenêtre et par compte, pas une par appel.
      if (maintenant - (this.dernierJournal.get(cle) ?? 0) >= fenetreMs) {
        this.dernierJournal.set(cle, maintenant);
        logger.warn('Observation : fréquence anormale (rien n\'est refusé)', {
          fonction,
          uid,
          appels: recents.length,
          fenetreSecondes: regle.fenetreSecondes,
          seuil: regle.seuil,
        });
      }
      if (this.alerter && recents.length >= regle.seuil * MULTIPLE_ALERTE_ADMIN) {
        if (maintenant - (this.derniereAlerte.get(cle) ?? 0) >= DELAI_ALERTE_ADMIN_MS) {
          this.derniereAlerte.set(cle, maintenant);
          try {
            await this.alerter({ uid, fonction, appels: recents.length, regle });
          } catch (e) {
            // Une notification en panne ne change pas le constat : le compte a bien dépassé le seuil.
            logger.error('Alerte d\'activité inhabituelle impossible', e);
          }
        }
      }
      return true;
    } catch (e) {
      logger.error('Observation de fréquence impossible', e);
      return false;
    }
  }

  private nettoyer(maintenant: number): void {
    for (const [cle, instants] of this.appels) {
      const fonction = cle.slice(0, cle.indexOf('|'));
      const fenetreMs = (this.regles[fonction]?.fenetreSecondes ?? 60) * 1000;
      if (instants.length === 0 || maintenant - instants[instants.length - 1] >= fenetreMs) {
        this.appels.delete(cle);
        this.dernierJournal.delete(cle);
      }
    }
    for (const [cle, instant] of this.derniereAlerte) {
      if (maintenant - instant >= DELAI_ALERTE_ADMIN_MS) this.derniereAlerte.delete(cle);
    }
  }
}

// ---------------------------------------------------------------------
// 2. Adresse e-mail non vérifiée sur les gestes qui touchent à l'argent
// ---------------------------------------------------------------------

/**
 * Note qu'un compte à l'e-mail non vérifié commande, recharge ou retire. On
 * ne refuse rien : le journal dit combien de clients réels seraient touchés
 * le jour où l'on exigera la vérification.
 */
export function observerEmail(fonction: string, auth: { uid: string; token: { email_verified?: boolean } } | undefined): void {
  try {
    if (auth && auth.token.email_verified !== true) {
      logger.info('Observation : e-mail non vérifié', { fonction, uid: auth.uid });
    }
  } catch (e) {
    logger.error('Observation d\'e-mail impossible', e);
  }
}

// ---------------------------------------------------------------------
// 3. Commandes de paiement en attente d'un même client
// ---------------------------------------------------------------------

/** Au-delà de ce nombre de paiements en attente chez un même client, on le signale. */
export const COMMANDES_EN_ATTENTE_OBSERVEES = 5;

/** Nombre de paiements en attente du client (0 si indisponible). Ne lève jamais d'erreur. */
export async function observerCommandesEnAttente(db: Firestore, uid: string | undefined): Promise<number> {
  try {
    if (!uid) return 0;
    const total = (
      await db.collection('commandes').where('clientId', '==', uid).where('statut', '==', STATUTS_COMMANDE.enAttente).count().get()
    ).data().count;
    if (total >= COMMANDES_EN_ATTENTE_OBSERVEES) {
      logger.warn('Observation : paiements en attente nombreux chez un même client (rien n\'est refusé)', {
        uid,
        enAttente: total,
        seuil: COMMANDES_EN_ATTENTE_OBSERVEES,
      });
    }
    return total;
  } catch (e) {
    logger.error('Observation des commandes en attente impossible', e);
    return 0;
  }
}

// ---------------------------------------------------------------------
// 4. Opérations sensibles de l'Admin : crédits de portefeuille, retraits
// ---------------------------------------------------------------------

/**
 * Plafonds journaliers PAR ADMIN, en observation : leur dépassement est
 * journalisé et notifié à tous les Admin, l'opération n'est pas refusée.
 * Valeurs de départ, à régler d'après l'usage réel.
 */
export const PLAFONDS_ADMIN_JOUR = {
  /** Total des crédits de portefeuille (ajustements positifs). */
  creditsFcfa: 150_000,
  /** Total des retraits versés. */
  versementsFcfa: 300_000,
  /** Nombre d'opérations sensibles (crédits, débits, retraits versés ou refusés). */
  operations: 15,
} as const;

export type TypeOperationAdmin = 'credit' | 'debit' | 'retrait_verse' | 'retrait_refuse';

export interface OperationAdmin {
  type: TypeOperationAdmin;
  /** Valeur absolue, en FCFA. */
  montantFcfa: number;
  clientId: string;
  /** Motif (ajustement) ou moyen de paiement (retrait). */
  detail?: string;
}

/** Prévient les Admin ; rend le nombre de téléphones atteints (voir `prevenirAdmins`). */
export type Prevenir = (push: EnvoiPush) => Promise<number>;

const fcfa = (montant: number) => `${montant.toLocaleString('fr-FR').replace(/[  ]/g, ' ')} FCFA`;
const nombre = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : 0);
const franchit = (avant: number, apres: number, plafond: number) => avant <= plafond && apres > plafond;

/** Nom du compte, à défaut son e-mail, à défaut le début de son identifiant : de quoi le reconnaître dans une notification. */
async function nomDe(db: Firestore, uid: string): Promise<string> {
  const reserve = `le compte ${uid.slice(0, 6)}…`;
  try {
    const profil = await db.collection('users').doc(uid).get();
    for (const champ of ['nom', 'email']) {
      const valeur = profil.get(champ);
      if (typeof valeur === 'string' && valeur.trim()) return valeur.trim().slice(0, 60);
    }
    return reserve;
  } catch {
    return reserve;
  }
}

/**
 * Note une opération sensible de l'Admin `adminId` dans son compteur du jour
 * (`controle_admin/{adminId}_{AAAA-MM-JJ}`, jamais lisible par l'app), la
 * journalise, et prévient TOUS les Admin d'un crédit, d'un retrait versé ou
 * d'un plafond dépassé : si le compte d'un Admin est piraté, le vrai
 * propriétaire le voit tout de suite sur son téléphone. Ne refuse rien, ne
 * lève jamais d'erreur.
 */
export async function observerOperationAdmin(
  db: Firestore,
  adminId: string,
  operation: OperationAdmin,
  maintenant: Date,
  prevenir?: Prevenir,
): Promise<void> {
  try {
    const jour = maintenant.toISOString().slice(0, 10);
    const ref = db.collection('controle_admin').doc(`${adminId}_${jour}`);
    const { avant, apres } = await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      const avant = {
        creditsFcfa: nombre(doc.get('creditsFcfa')),
        versementsFcfa: nombre(doc.get('versementsFcfa')),
        operations: nombre(doc.get('operations')),
      };
      const apres = {
        creditsFcfa: avant.creditsFcfa + (operation.type === 'credit' ? operation.montantFcfa : 0),
        versementsFcfa: avant.versementsFcfa + (operation.type === 'retrait_verse' ? operation.montantFcfa : 0),
        operations: avant.operations + 1,
      };
      tx.set(ref, { adminId, jour, ...apres, majLe: Timestamp.fromDate(maintenant) }, { merge: true });
      return { avant, apres };
    });

    const depassements: string[] = [];
    if (franchit(avant.creditsFcfa, apres.creditsFcfa, PLAFONDS_ADMIN_JOUR.creditsFcfa)) {
      depassements.push(`plafond de crédits du jour (${fcfa(PLAFONDS_ADMIN_JOUR.creditsFcfa)}) dépassé : ${fcfa(apres.creditsFcfa)}`);
    }
    if (franchit(avant.versementsFcfa, apres.versementsFcfa, PLAFONDS_ADMIN_JOUR.versementsFcfa)) {
      depassements.push(`plafond de retraits versés du jour (${fcfa(PLAFONDS_ADMIN_JOUR.versementsFcfa)}) dépassé : ${fcfa(apres.versementsFcfa)}`);
    }
    if (franchit(avant.operations, apres.operations, PLAFONDS_ADMIN_JOUR.operations)) {
      depassements.push(`plus de ${PLAFONDS_ADMIN_JOUR.operations} opérations sensibles dans la journée (${apres.operations})`);
    }

    logger.info('Contrôle Admin : opération sensible', { adminId, ...operation, jour, ...apres });
    if (depassements.length > 0) {
      logger.warn('Contrôle Admin : plafond journalier dépassé (observation : rien n\'est refusé)', {
        adminId,
        jour,
        depassements,
        ...apres,
      });
    }

    const notifiable = operation.type === 'credit' || operation.type === 'retrait_verse' || depassements.length > 0;
    if (!prevenir || !notifiable) return;
    const [admin, client] = await Promise.all([nomDe(db, adminId), nomDe(db, operation.clientId)]);
    const phrases: string[] = [];
    if (operation.type === 'credit') {
      phrases.push(
        `${fcfa(operation.montantFcfa)} ajoutés au portefeuille de ${client}, par ${admin}.` +
          (operation.detail ? ` Motif : ${operation.detail.slice(0, 80)}.` : ''),
      );
    } else if (operation.type === 'retrait_verse') {
      phrases.push(`${fcfa(operation.montantFcfa)} versés à ${client}${operation.detail ? ` (${operation.detail})` : ''}, par ${admin}.`);
    } else {
      phrases.push(`Opération de ${admin} sur le compte de ${client} : ${operation.type === 'debit' ? 'débit' : 'retrait refusé'} de ${fcfa(operation.montantFcfa)}.`);
    }
    phrases.push(...depassements.map((d) => `Attention : ${d}.`));
    phrases.push('Ce n\'est pas vous ? Voir le journal Admin.');
    await prevenir({
      titre: depassements.length > 0 ? 'Admin : plafond du jour dépassé' : operation.type === 'credit' ? 'Admin : crédit de portefeuille' : 'Admin : retrait versé',
      corps: phrases.join(' '),
      canal: 'messages',
      lien: LIENS.admin,
      donnees: { type: 'controle_admin', operation: operation.type },
      dureeVieSecondes: 24 * 3600,
    });
  } catch (e) {
    logger.error('Contrôle Admin : observation impossible', e);
  }
}

/**
 * Observation d'un retrait traité par l'Admin (`traiterRetrait` a réussi) :
 * relit le retrait enregistré pour en connaître le montant, le client et le
 * moyen, puis note l'opération. `statut` est celui rendu par `traiterRetrait`.
 */
export async function observerRetraitTraite(
  db: Firestore,
  adminId: string | undefined,
  donnees: unknown,
  statut: string,
  maintenant: Date,
  prevenir?: Prevenir,
): Promise<void> {
  try {
    const retraitId = (donnees as { retraitId?: unknown } | null)?.retraitId;
    if (!adminId || typeof retraitId !== 'string') return;
    const retrait = await db.collection('retraits').doc(retraitId).get();
    const montant = retrait.get('montantFcfa');
    const clientId = retrait.get('clientId');
    if (!retrait.exists || typeof montant !== 'number' || typeof clientId !== 'string') return;
    const moyen = retrait.get('moyen');
    await observerOperationAdmin(
      db,
      adminId,
      {
        type: statut === STATUTS_RETRAIT.verse ? 'retrait_verse' : 'retrait_refuse',
        montantFcfa: montant,
        clientId,
        detail: moyen === 'ORANGE_MONEY' ? 'Orange Money' : moyen === 'WAVE' ? 'Wave' : undefined,
      },
      maintenant,
      prevenir,
    );
  } catch (e) {
    logger.error('Contrôle Admin : observation du retrait impossible', e);
  }
}

/**
 * Observation d'un ajustement de portefeuille (`ajusterPortefeuille` a
 * réussi) : les données sont celles de la demande, déjà validées par la
 * fonction. Un crédit (montant positif) prévient les Admin.
 */
export async function observerAjustement(
  db: Firestore,
  adminId: string | undefined,
  donnees: unknown,
  maintenant: Date,
  prevenir?: Prevenir,
): Promise<void> {
  try {
    const d = (donnees ?? {}) as { clientId?: unknown; montantFcfa?: unknown; motif?: unknown };
    if (!adminId || typeof d.clientId !== 'string' || typeof d.montantFcfa !== 'number' || d.montantFcfa === 0) return;
    await observerOperationAdmin(
      db,
      adminId,
      {
        type: d.montantFcfa > 0 ? 'credit' : 'debit',
        montantFcfa: Math.abs(d.montantFcfa),
        clientId: d.clientId,
        detail: typeof d.motif === 'string' ? d.motif.trim() : undefined,
      },
      maintenant,
      prevenir,
    );
  } catch (e) {
    logger.error('Contrôle Admin : observation de l\'ajustement impossible', e);
  }
}
