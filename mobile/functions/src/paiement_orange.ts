import { Timestamp, type Firestore, type QueryDocumentSnapshot } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import {
  ErreurFournisseur,
  FOURNISSEUR_ORANGE,
  type CreateurSession,
  type EvenementPaiement,
  type FournisseurDuMoyen,
  type FournisseurPaiement,
  type SessionPaiement,
} from './fournisseurs';
import type { Messagerie } from './notifications';
import {
  ClientOrangeMoney,
  ErreurNotificationOrange,
  ErreurOrangeMoney,
  lireNotification,
  URL_ORANGE_MONEY,
  type StatutTransaction,
  type TransactionOrangeMoney,
} from './orange_money';
import { DUREE_PAIEMENT_MS, STATUTS_COMMANDE, traiterEvenement, type ResultatWebhook } from './paiements';
import {
  DUREE_RECHARGE_MS,
  estReferenceRecharge,
  STATUTS_RECHARGE,
  traiterEvenementRecharge,
  type ResultatRecharge,
} from './portefeuille';

/**
 * Paiement par Orange Money (Sonatel), branché sur le parcours de paiement
 * existant (`paiements.ts`, `portefeuille.ts`) :
 *
 *   creerPaiement / creerRecharge ──> demande de paiement chez Orange : QR
 *       code et lien Max It (session « om_<référence> », usage unique) ; la
 *       commande ou la recharge attend, comme avec Wave.
 *   notification d'Orange (webhookOrangeMoney) ──> clé vérifiée, puis la
 *       transaction est RELUE chez Orange (son contenu seul ne fait jamais
 *       foi : montant, référence, marchand payé et statut viennent d'Orange)
 *       ──> course créée ou recharge créditée, par le traitement commun.
 *   surveillance (toutes les 5 minutes) ──> pendant 1 heure, les demandes
 *       Orange sans issue sont relues chez Orange (notification perdue,
 *       paiement arrivé après l'expiration ou après un premier refus).
 *   remboursement ──> sur le solde Sprint (l'API d'Orange n'en a pas).
 *
 * L'en-tête `X-Sonatel-Signature` n'est pas vérifié : « évolution à venir,
 * ne pas en tenir compte » (support d'Orange, 29 octobre 2026) ; la relecture
 * chez Orange suffit.
 */

export const PREFIXE_SESSION_ORANGE = 'om_';

/** Nom affiché au client dans Max It et Orange Money. */
export const NOM_MARCHAND_ORANGE = 'Sprint';

/**
 * Validité de la demande chez Orange : 2 minutes de moins que la commande ou
 * la recharge (20 minutes), pour que la confirmation d'Orange arrive avant
 * leur expiration.
 */
export const VALIDITE_ORANGE_SECONDES = (Math.min(DUREE_PAIEMENT_MS, DUREE_RECHARGE_MS) - 2 * 60 * 1000) / 1000;

/** Durée, après la demande, pendant laquelle la surveillance relit le paiement chez Orange. */
export const FENETRE_RELECTURE_MS = 60 * 60 * 1000;

/** Recherches chez Orange au plus par passage de la surveillance (bac à sable : 60 requêtes par minute). */
export const RELECTURES_MAX = 20;

/** Documents lus au plus par collection et par passage (ceux de la dernière heure). */
const LECTURES_MAX = 500;

/** Statuts d'une transaction qui n'est pas encore finie. */
const STATUTS_EN_COURS: readonly StatutTransaction[] = ['ACCEPTED', 'INITIATED', 'PENDING', 'PRE_INITIATED'];

/** Types de transaction qui paient un marchand (un dépôt « CASHIN » ne nous paie jamais). */
const TYPES_PAIEMENT = ['MERCHANT_PAYMENT', 'WEB_PAYMENT'];

/** Statuts où un paiement réussi chez Orange reste à appliquer (course, remboursement ou crédit). */
const A_RELIRE = {
  commandes: [STATUTS_COMMANDE.enAttente, STATUTS_COMMANDE.expiree, STATUTS_COMMANDE.echouee] as string[],
  recharges: [STATUTS_RECHARGE.enAttente, STATUTS_RECHARGE.expiree, STATUTS_RECHARGE.echouee] as string[],
};

export interface ConfigOrange {
  client: ClientOrangeMoney;
  /** Code marchand à 6 chiffres (Secret Manager : hors du dépôt public). */
  codeMarchand: string;
}

/**
 * Configuration à partir des valeurs lues dans Secret Manager ; `null` s'il en
 * manque une (Orange Money est alors indisponible, le reste du paiement
 * continue).
 */
export function configurerOrange(
  valeurs: { idClient: string; secretClient: string; codeMarchand: string },
  urlBase: string = URL_ORANGE_MONEY.bacASable,
  fetcher?: typeof fetch,
): ConfigOrange | null {
  const idClient = valeurs.idClient.trim();
  const secretClient = valeurs.secretClient.trim();
  const codeMarchand = valeurs.codeMarchand.trim();
  if (!idClient || !secretClient || !/^\d{6}$/.test(codeMarchand)) return null;
  return { client: new ClientOrangeMoney({ urlBase, idClient, secretClient, fetcher }), codeMarchand };
}

/**
 * Qui encaisse chaque moyen de paiement mobile money : Orange Money par
 * Orange, jamais par le faux opérateur (une course « payée » par la
 * simulation ne coûterait rien) ; Wave par [wave].
 */
export function fournisseursDuMoyen(wave: CreateurSession, orange: () => CreateurSession): FournisseurDuMoyen {
  return (methode) => {
    if (methode === 'WAVE') return wave;
    if (methode === 'ORANGE_MONEY') return orange();
    throw new ErreurFournisseur(`Aucun fournisseur pour ${methode}.`);
  };
}

/** Crée les demandes de paiement Orange Money. */
export class FournisseurOrangeMoney implements CreateurSession {
  readonly nom = FOURNISSEUR_ORANGE;

  constructor(
    private readonly config: ConfigOrange,
    private readonly horloge: () => Date = () => new Date(),
  ) {}

  async creerSession(reference: string, montantFcfa: number): Promise<SessionPaiement> {
    const debut = this.horloge();
    const qr = await this.config.client.genererQrCode({
      codeMarchand: this.config.codeMarchand,
      nomMarchand: NOM_MARCHAND_ORANGE,
      montantFcfa,
      reference,
      validiteSecondes: VALIDITE_ORANGE_SECONDES,
      usageUnique: true,
    });
    // Max It d'abord (l'app d'Orange la plus répandue), puis Orange Money, puis la page de paiement.
    const lienPaiement = qr.lienMaxIt ?? qr.lienOrangeMoney ?? qr.lienCourt;
    if (lienPaiement === undefined) throw new ErreurFournisseur('Orange n\'a donné aucun lien de paiement.');
    return {
      sessionId: `${PREFIXE_SESSION_ORANGE}${reference}`,
      lienPaiement,
      relectureFinLe: new Date(debut.getTime() + FENETRE_RELECTURE_MS),
    };
  }
}

export type ResultatOrange = ResultatWebhook | ResultatRecharge | 'en_attente' | 'non_confirmee';

/**
 * La transaction paie-t-elle Sprint ? En production, seul NOTRE code marchand
 * compte : un autre marchand peut porter notre référence. Dans le bac à
 * sable, Orange encaisse les paiements sur un code marchand de test qui lui
 * appartient (OFMS, support d'Orange, 29 octobre 2026) : le code n'y est pas
 * comparé ; référence, montant, devise, type et statut relus chez Orange
 * restent exigés, et aucun argent réel n'est en jeu.
 */
export function paieSprint(transaction: TransactionOrangeMoney, config: ConfigOrange): boolean {
  return config.client.estBacASable || transaction.codeMarchand === config.codeMarchand;
}

/**
 * Applique une transaction LUE CHEZ ORANGE à la commande ou à la recharge
 * qu'elle paie (sa référence). Rien n'est fait pour une transaction sans
 * référence, qui ne paie pas Sprint ([paieSprint]), d'un autre type ou pas
 * encore finie. Rejouer la même transaction ne crée jamais une deuxième
 * course ni ne crédite deux fois (traitement commun idempotent) ; montant ou
 * devise différents : anomalie.
 */
export async function appliquerTransactionOrange(
  db: Firestore,
  transaction: TransactionOrangeMoney,
  config: ConfigOrange,
  fournisseurRemboursement: FournisseurPaiement,
  maintenant: Date,
  messagerie?: Messagerie,
): Promise<ResultatOrange> {
  const reference = transaction.reference;
  if (!reference) return 'non_confirmee';
  if (!paieSprint(transaction, config)) {
    logger.error('Transaction Orange qui ne paie pas notre code marchand', {
      transactionId: transaction.transactionId,
      reference,
    });
    return 'non_confirmee';
  }
  if (transaction.type !== undefined && !TYPES_PAIEMENT.includes(transaction.type)) return 'non_confirmee';
  if (transaction.statut === undefined || STATUTS_EN_COURS.includes(transaction.statut)) return 'en_attente';

  const evenement: EvenementPaiement = {
    sessionId: `${PREFIXE_SESSION_ORANGE}${reference}`,
    commandeId: reference,
    reussi: transaction.statut === 'SUCCESS',
    // Montant ou devise absents : différents de la demande, donc anomalie.
    montantFcfa: transaction.montantFcfa ?? 0,
    devise: transaction.devise ?? '',
  };
  // Une commande ou recharge inconnue (autre référence) est ignorée par le traitement commun.
  return estReferenceRecharge(reference)
    ? traiterEvenementRecharge(db, evenement, maintenant)
    : traiterEvenement(db, fournisseurRemboursement, evenement, maintenant, messagerie);
}

/**
 * Notification d'Orange : clé vérifiée, puis la transaction est relue chez
 * Orange par son identifiant, et seule cette lecture est appliquée.
 */
export async function traiterNotificationOrange(
  db: Firestore,
  config: ConfigOrange,
  autorisation: string | undefined,
  corpsBrut: Buffer,
  cleNotification: string,
  fournisseurRemboursement: FournisseurPaiement,
  maintenant: Date,
  messagerie?: Messagerie,
): Promise<ResultatOrange> {
  const notification = lireNotification(autorisation, corpsBrut, cleNotification);
  const transactions = await config.client.rechercherTransactions({ transactionId: notification.transactionId });
  const transaction = transactions.find((t) => t.transactionId === notification.transactionId);
  if (transaction === undefined) {
    logger.warn('Notification Orange : transaction introuvable chez Orange', { transactionId: notification.transactionId });
    return 'non_confirmee';
  }
  if (notification.reference !== undefined && transaction.reference !== notification.reference) {
    logger.error('Notification Orange : référence différente de celle enregistrée chez Orange', {
      transactionId: notification.transactionId,
    });
    return 'non_confirmee';
  }
  return appliquerTransactionOrange(db, transaction, config, fournisseurRemboursement, maintenant, messagerie);
}

/**
 * Réponse HTTP à une notification d'Orange. Orange relivre sur un 5xx (avec
 * des délais croissants) et abandonne sur un 4xx : 405 hors POST, 401 pour une
 * notification non authentifiée, 503 si Orange Money n'est pas configuré, 500
 * si Orange ou la base sont momentanément injoignables, 202 (corps vide, comme
 * le recommande Orange) dans tous les autres cas, la surveillance rattrapant
 * un paiement encore en cours.
 */
export async function repondreNotificationOrange(
  db: Firestore,
  config: ConfigOrange | null,
  cleNotification: string,
  requete: { methode: string; autorisation?: string; corpsBrut: Buffer },
  fournisseurRemboursement: () => Promise<FournisseurPaiement>,
  maintenant: Date,
  messagerie?: Messagerie,
): Promise<{ statut: number; corps: string; resultat?: ResultatOrange }> {
  if (requete.methode !== 'POST') return { statut: 405, corps: 'POST uniquement.' };
  if (config === null || !cleNotification.trim()) {
    logger.error('Notification Orange reçue alors qu\'Orange Money n\'est pas configuré.');
    return { statut: 503, corps: 'Orange Money indisponible.' };
  }
  try {
    const resultat = await traiterNotificationOrange(
      db,
      config,
      requete.autorisation,
      requete.corpsBrut,
      cleNotification.trim(),
      await fournisseurRemboursement(),
      maintenant,
      messagerie,
    );
    logger.info('Notification Orange', { resultat });
    return { statut: 202, corps: '', resultat };
  } catch (e) {
    if (e instanceof ErreurNotificationOrange) {
      logger.warn('Notification Orange refusée', { raison: e.message });
      return { statut: 401, corps: 'Notification refusée.' };
    }
    logger.error('Notification Orange en erreur', e);
    return { statut: 500, corps: 'Erreur interne.' };
  }
}

export interface BilanRattrapage {
  /** Demandes relues chez Orange. */
  verifiees: number;
  /** Paiements réussis appliqués (course, remboursement ou crédit). */
  appliquees: number;
  erreurs: number;
  /** Demandes laissées au passage suivant (plafond de recherches atteint). */
  reportees: number;
}

/**
 * Rattrapage (surveillance) : les commandes et recharges Orange dont la
 * fenêtre de relecture court encore et qui n'ont pas d'issue (en attente,
 * expirées ou refusées) sont relues chez Orange par leur référence ; un
 * paiement réussi est appliqué même si sa notification s'est perdue : course
 * créée, ou argent rendu sur le solde, ou recharge créditée. Les échecs sont
 * laissés à la notification et à l'expiration normale (le client a pu
 * réessayer). Celles encore en attente passent en premier ; au plus [max]
 * recherches par passage, et aucune de plus si Orange demande de ralentir.
 */
export async function rattraperOrange(
  db: Firestore,
  config: ConfigOrange,
  fournisseurRemboursement: FournisseurPaiement,
  maintenant: Date,
  messagerie?: Messagerie,
  max = RELECTURES_MAX,
): Promise<BilanRattrapage> {
  const bilan: BilanRattrapage = { verifiees: 0, appliquees: 0, erreurs: 0, reportees: 0 };
  const lire = (collection: 'commandes' | 'recharges') =>
    db
      .collection(collection)
      .where('relectureFinLe', '>', Timestamp.fromDate(maintenant))
      .orderBy('relectureFinLe')
      .limit(LECTURES_MAX)
      .get();
  const [commandes, recharges] = await Promise.all([lire('commandes'), lire('recharges')]);
  const sansIssue = (statuts: string[]) => (doc: QueryDocumentSnapshot) =>
    doc.get('fournisseur') === FOURNISSEUR_ORANGE && statuts.includes(doc.get('statut'));
  const enAttente = (doc: QueryDocumentSnapshot) =>
    doc.get('statut') === STATUTS_COMMANDE.enAttente || doc.get('statut') === STATUTS_RECHARGE.enAttente;
  const aRelire = [
    ...commandes.docs.filter(sansIssue(A_RELIRE.commandes)),
    ...recharges.docs.filter(sansIssue(A_RELIRE.recharges)),
  ].sort(
    (a, b) =>
      Number(!enAttente(a)) - Number(!enAttente(b)) ||
      (a.get('relectureFinLe') as Timestamp).toMillis() - (b.get('relectureFinLe') as Timestamp).toMillis(),
  );

  for (const doc of aRelire) {
    if (bilan.verifiees >= max) break;
    bilan.verifiees++;
    try {
      const transactions = await config.client.rechercherTransactions({ reference: doc.id });
      // Un paiement réussi qui paie Sprint (un autre marchand peut porter notre référence).
      const reussie = transactions.find((t) => t.reference === doc.id && t.statut === 'SUCCESS' && paieSprint(t, config));
      if (reussie === undefined) continue;
      const resultat = await appliquerTransactionOrange(db, reussie, config, fournisseurRemboursement, maintenant, messagerie);
      if (resultat === 'course_creee' || resultat === 'recharge_creditee' || resultat === 'rembourse') bilan.appliquees++;
    } catch (e) {
      bilan.erreurs++;
      logger.warn('Rattrapage Orange impossible', { reference: doc.id, erreur: String(e) });
      if (e instanceof ErreurOrangeMoney && e.statutHttp === 429) break;
    }
  }
  bilan.reportees = aRelire.length - bilan.verifiees;
  return bilan;
}
