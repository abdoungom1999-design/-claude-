import { randomBytes } from 'node:crypto';
import { Timestamp, type DocumentReference, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';
import {
  FOURNISSEUR_ORANGE,
  type CreateurSession,
  type EvenementPaiement,
  type FournisseurDuMoyen,
  type SessionPaiement,
} from './fournisseurs';
import { METHODES_RECHARGE, verifierMethode, type Methode } from './methodes_paiement';

/**
 * Portefeuille Sprint : crédit prépayé du client, utilisable uniquement
 * pour payer des courses (non retirable).
 *
 * Principe : le solde n'est jamais modifiable depuis l'app. Seul ce module
 * l'écrit, toujours dans une transaction qui écrit aussi une ligne du
 * livre de comptes (`portefeuilles/{uid}/mouvements/{id}`, en ajout seul).
 * Chaque mouvement a un identifiant déterministe (recharge, course,
 * remboursement) : rejouer un webhook ou un remboursement ne crédite ni ne
 * débite jamais deux fois.
 *
 *   creerRecharge ──> recharge "en_attente" + lien de paiement (Wave)
 *   webhook signé ──> recharge "reussie" + solde crédité + mouvement
 *                └──> recharge "echouee" (refus, annulation)
 *   surveillance  ──> recharge "expiree" si jamais payée
 *   creerPaiement (PORTEFEUILLE) ──> solde débité + course créée, atomique
 *   annulation / remboursement d'une course payée par solde ──> solde recrédité
 */

export const RECHARGE_MIN_FCFA = 500;
export const RECHARGE_MAX_FCFA = 100_000;
export const SOLDE_MAX_FCFA = 200_000;

/** Recharges en attente de paiement, au plus, par client (anti-abus). */
export const RECHARGES_EN_ATTENTE_MAX = 5;

/** Une recharge non finalisée expire au bout de 20 minutes. */
export const DUREE_RECHARGE_MS = 20 * 60 * 1000;

/** Préfixe de `client_reference` des sessions de paiement des recharges. */
export const PREFIXE_RECHARGE = 'rch_';

export const STATUTS_RECHARGE = {
  enAttente: 'en_attente',
  reussie: 'reussie',
  echouee: 'echouee',
  expiree: 'expiree',
  anomalie: 'anomalie',
} as const;

export const TYPES_MOUVEMENT = {
  recharge: 'recharge',
  paiementCourse: 'paiement_course',
  remboursement: 'remboursement',
  ajustementAdmin: 'ajustement_admin',
} as const;

export const estReferenceRecharge = (reference: string): boolean => reference.startsWith(PREFIXE_RECHARGE);

export const refPortefeuille = (db: Firestore, uid: string) => db.collection('portefeuilles').doc(uid);

/** Solde d'un portefeuille (0 tant qu'il n'a jamais servi). */
export function solde(doc: { get(champ: string): unknown }): number {
  const valeur = doc.get('soldeFcfa');
  return typeof valeur === 'number' && Number.isInteger(valeur) ? valeur : 0;
}

/**
 * Écrit un mouvement et le nouveau solde, dans la transaction [tx]. Le
 * portefeuille doit déjà avoir été lu dans [tx] (règle Firestore : toutes
 * les lectures avant les écritures). Un mouvement déjà présent (même
 * identifiant) n'est jamais réécrit : l'appelant doit l'avoir vérifié.
 */
export function ecrireMouvement(
  tx: Transaction,
  db: Firestore,
  uid: string,
  soldeAvant: number,
  mouvement: {
    id: string;
    type: (typeof TYPES_MOUVEMENT)[keyof typeof TYPES_MOUVEMENT];
    montantFcfa: number;
    reference: string | null;
    note?: string;
  },
  maintenant: Date,
): number {
  const soldeApres = soldeAvant + mouvement.montantFcfa;
  const ref = refPortefeuille(db, uid);
  tx.set(ref, { soldeFcfa: soldeApres, majLe: Timestamp.fromDate(maintenant) }, { merge: true });
  tx.create(ref.collection('mouvements').doc(mouvement.id), {
    type: mouvement.type,
    montantFcfa: mouvement.montantFcfa,
    soldeApresFcfa: soldeApres,
    reference: mouvement.reference,
    ...(mouvement.note ? { note: mouvement.note } : {}),
    creeLe: Timestamp.fromDate(maintenant),
  });
  return soldeApres;
}

export function objet(valeur: unknown): Record<string, unknown> {
  return typeof valeur === 'object' && valeur !== null && !Array.isArray(valeur)
    ? (valeur as Record<string, unknown>)
    : {};
}

// ---------------------------------------------------------------------
// 1. Demande de recharge (callable `creerRecharge`)
// ---------------------------------------------------------------------

export interface RechargeCreee {
  rechargeId: string;
  lienPaiement: string;
  montantFcfa: number;
}

export function validerRecharge(
  donnees: unknown,
  methodes: readonly Methode[] = METHODES_RECHARGE,
): { montantFcfa: number; methodePaiement: Methode } {
  const d = objet(donnees);
  const montant = d.montantFcfa;
  if (typeof montant !== 'number' || !Number.isInteger(montant)) {
    throw new HttpsError('invalid-argument', 'Montant de recharge invalide.');
  }
  if (montant < RECHARGE_MIN_FCFA) {
    throw new HttpsError('invalid-argument', `La recharge minimale est de ${RECHARGE_MIN_FCFA} FCFA.`);
  }
  if (montant > RECHARGE_MAX_FCFA) {
    throw new HttpsError('invalid-argument', `La recharge maximale est de ${RECHARGE_MAX_FCFA} FCFA.`);
  }
  return { montantFcfa: montant, methodePaiement: verifierMethode(d.methodePaiement, methodes, 'recharger') };
}

/**
 * [fournisseurs] : qui encaisse le moyen choisi (Wave, Orange Money).
 * [methodes] : moyens acceptés (ceux ouverts aux clients, sauf essai).
 */
export async function creerRecharge(
  db: Firestore,
  fournisseurs: FournisseurDuMoyen,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
  methodes: readonly Methode[] = METHODES_RECHARGE,
): Promise<RechargeCreee> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous pour recharger votre portefeuille.');
  const profil = await db.collection('users').doc(uid).get();
  if (!profil.exists) throw new HttpsError('permission-denied', 'Profil introuvable.');
  if (profil.get('role') !== 'client') {
    throw new HttpsError('permission-denied', 'Le portefeuille est réservé aux clients.');
  }
  const statutCompte = profil.get('statutCompte');
  if (statutCompte === 'suspendu' || statutCompte === 'banni') {
    throw new HttpsError('permission-denied', 'Votre compte ne permet pas de recharger le portefeuille.');
  }
  const { montantFcfa, methodePaiement } = validerRecharge(donnees, methodes);

  const soldeActuel = solde(await refPortefeuille(db, uid).get());
  if (soldeActuel + montantFcfa > SOLDE_MAX_FCFA) {
    const possible = Math.max(0, SOLDE_MAX_FCFA - soldeActuel);
    throw new HttpsError(
      'failed-precondition',
      `Le solde du portefeuille est plafonné à ${SOLDE_MAX_FCFA} FCFA. Vous pouvez encore recharger ${possible} FCFA.`,
      { raison: 'plafond', possibleFcfa: possible },
    );
  }

  const enAttente = await db
    .collection('recharges')
    .where('clientId', '==', uid)
    .where('statut', '==', STATUTS_RECHARGE.enAttente)
    .get();
  const vivantes = enAttente.docs.filter((d) => {
    const expireLe = d.get('expireLe') as Timestamp | undefined;
    return expireLe && expireLe.toMillis() > maintenant.getTime();
  });
  if (vivantes.length >= RECHARGES_EN_ATTENTE_MAX) {
    throw new HttpsError('resource-exhausted', 'Trop de recharges en attente. Terminez-en une ou patientez quelques minutes.');
  }

  const ref = db.collection('recharges').doc(`${PREFIXE_RECHARGE}${randomBytes(12).toString('hex')}`);
  let fournisseur: CreateurSession;
  let session: SessionPaiement;
  try {
    fournisseur = fournisseurs(methodePaiement);
    session = await fournisseur.creerSession(ref.id, montantFcfa);
  } catch (e) {
    logger.error('Session de recharge impossible', e);
    throw new HttpsError('unavailable', 'Le paiement est momentanément indisponible. Réessayez.');
  }
  await ref.create({
    clientId: uid,
    statut: STATUTS_RECHARGE.enAttente,
    montantFcfa,
    methodePaiement,
    fournisseur: fournisseur.nom,
    sessionPaiementId: session.sessionId,
    lienPaiement: session.lienPaiement,
    creeLe: Timestamp.fromDate(maintenant),
    expireLe: Timestamp.fromDate(new Date(maintenant.getTime() + DUREE_RECHARGE_MS)),
    ...(session.relectureFinLe ? { relectureFinLe: Timestamp.fromDate(session.relectureFinLe) } : {}),
  });
  return { rechargeId: ref.id, lienPaiement: session.lienPaiement, montantFcfa };
}

// ---------------------------------------------------------------------
// 2. Confirmation du fournisseur (webhook, références "rch_…")
// ---------------------------------------------------------------------

export type ResultatRecharge = 'recharge_creditee' | 'deja_traite' | 'echec_enregistre' | 'anomalie' | 'inconnue';

/**
 * Traite l'événement (déjà vérifié par signature) d'une recharge. Le
 * solde n'est crédité qu'ici, jamais sur la foi de l'app. Rejouer le même
 * événement ne crédite jamais deux fois : la recharge n'est créditée que
 * depuis "en_attente", "expiree" ou "echouee" (paiement arrivé après
 * l'expiration, ou réussi après un premier refus, par exemple un nouvel
 * essai sur le même QR code Orange Money : l'argent est bien encaissé, il
 * est crédité).
 */
export async function traiterEvenementRecharge(
  db: Firestore,
  evenement: EvenementPaiement,
  maintenant: Date,
): Promise<ResultatRecharge> {
  const refRecharge = db.collection('recharges').doc(evenement.commandeId);
  return db.runTransaction(async (tx): Promise<ResultatRecharge> => {
    const recharge = await tx.get(refRecharge);
    if (!recharge.exists || recharge.get('sessionPaiementId') !== evenement.sessionId) return 'inconnue';
    const statut = recharge.get('statut') as string;
    const rattrapable = statut === STATUTS_RECHARGE.expiree || statut === STATUTS_RECHARGE.echouee;
    if (statut !== STATUTS_RECHARGE.enAttente && !(evenement.reussi && rattrapable)) return 'deja_traite';

    if (!evenement.reussi) {
      tx.update(refRecharge, { statut: STATUTS_RECHARGE.echouee, termineeLe: Timestamp.fromDate(maintenant) });
      return 'echec_enregistre';
    }

    const montantFcfa = recharge.get('montantFcfa') as number;
    const clientId = recharge.get('clientId') as string;
    if (evenement.montantFcfa !== montantFcfa || evenement.devise !== 'XOF') {
      logger.error('Montant rechargé différent de la demande', { recharge: refRecharge.id, evenement, montantFcfa });
      tx.update(refRecharge, { statut: STATUTS_RECHARGE.anomalie, motif: 'montant', termineeLe: Timestamp.fromDate(maintenant) });
      return 'anomalie';
    }

    const portefeuille = await tx.get(refPortefeuille(db, clientId));
    const soldeAvant = solde(portefeuille);
    if (soldeAvant + montantFcfa > SOLDE_MAX_FCFA) {
      // Deux recharges concurrentes ont dépassé le plafond : l'argent est
      // encaissé mais non crédité. Visible de l'Admin, à rembourser.
      logger.error('Recharge au-delà du plafond', { recharge: refRecharge.id, clientId, soldeAvant, montantFcfa });
      tx.update(refRecharge, { statut: STATUTS_RECHARGE.anomalie, motif: 'plafond', termineeLe: Timestamp.fromDate(maintenant) });
      return 'anomalie';
    }
    ecrireMouvement(
      tx,
      db,
      clientId,
      soldeAvant,
      { id: `recharge_${refRecharge.id}`, type: TYPES_MOUVEMENT.recharge, montantFcfa, reference: refRecharge.id },
      maintenant,
    );
    tx.update(refRecharge, { statut: STATUTS_RECHARGE.reussie, creditee: true, termineeLe: Timestamp.fromDate(maintenant) });
    return 'recharge_creditee';
  });
}

/** Recharges jamais payées : marquées expirées (le client peut en refaire une). */
export async function surveillerRecharges(db: Firestore, maintenant: Date): Promise<number> {
  let expirees = 0;
  const enAttente = await db.collection('recharges').where('statut', '==', STATUTS_RECHARGE.enAttente).get();
  for (const doc of enAttente.docs) {
    const expireLe = doc.get('expireLe') as Timestamp | undefined;
    if (!expireLe || expireLe.toMillis() > maintenant.getTime()) continue;
    const expiree = await db.runTransaction(async (tx) => {
      const actuelle = await tx.get(doc.ref);
      if (actuelle.get('statut') !== STATUTS_RECHARGE.enAttente) return false;
      tx.update(doc.ref, { statut: STATUTS_RECHARGE.expiree, termineeLe: Timestamp.fromDate(maintenant) });
      return true;
    });
    if (expiree) expirees++;
  }
  return expirees;
}

// ---------------------------------------------------------------------
// 3. Paiement d'une course par le solde (appelé par `creerPaiement`)
// ---------------------------------------------------------------------

export const FOURNISSEUR_PORTEFEUILLE = 'portefeuille';
export const METHODE_PORTEFEUILLE = 'PORTEFEUILLE';

/**
 * Commandes remboursées sur le solde Sprint plutôt que chez le fournisseur :
 * celles payées avec le solde, et celles payées par Orange Money, dont l'API
 * n'a pas de remboursement (décision du client, 29 octobre 2026 : plus sûr, et
 * le client garde son crédit chez Sprint).
 */
export const FOURNISSEURS_REMBOURSES_SUR_SOLDE: readonly string[] = [FOURNISSEUR_PORTEFEUILLE, FOURNISSEUR_ORANGE];

/**
 * Débite le solde de [prixFcfa] à l'intérieur de la transaction [tx] qui
 * crée aussi la course. Lève `solde-insuffisant` sans rien écrire si le
 * solde ne suffit pas (le client choisit alors un mode mobile money).
 * [portefeuille] est le document déjà lu dans [tx].
 */
export function debiterPourCourse(
  tx: Transaction,
  db: Firestore,
  uid: string,
  portefeuille: { get(champ: string): unknown },
  commandeId: string,
  prixFcfa: number,
  maintenant: Date,
): void {
  const soldeAvant = solde(portefeuille);
  if (soldeAvant < prixFcfa) {
    throw new HttpsError(
      'failed-precondition',
      `Solde insuffisant : ${soldeAvant} FCFA disponibles pour une course de ${prixFcfa} FCFA. Rechargez votre solde ou choisissez Wave.`,
      { raison: 'solde-insuffisant', soldeFcfa: soldeAvant },
    );
  }
  ecrireMouvement(
    tx,
    db,
    uid,
    soldeAvant,
    { id: `course_${commandeId}`, type: TYPES_MOUVEMENT.paiementCourse, montantFcfa: -prixFcfa, reference: commandeId },
    maintenant,
  );
}

export const lirePortefeuille = (tx: Transaction, db: Firestore, uid: string) => tx.get(refPortefeuille(db, uid));

// ---------------------------------------------------------------------
// 4. Remboursement sur le solde
// ---------------------------------------------------------------------

/**
 * Rend au portefeuille le prix d'une commande payée avec le solde ou par
 * Orange Money ([FOURNISSEURS_REMBOURSES_SUR_SOLDE]). Jamais bloqué par le
 * plafond (un remboursement doit toujours aboutir) et idempotent : le
 * mouvement `remboursement_{commande}` n'existe qu'une fois. Renvoie `false`
 * si la commande ne se rembourse pas sur le solde.
 */
export async function rembourserSurPortefeuille(
  db: Firestore,
  refCommande: DocumentReference,
  motif: string,
  maintenant: Date,
): Promise<boolean> {
  return db.runTransaction(async (tx) => {
    const commande = await tx.get(refCommande);
    if (!commande.exists || !FOURNISSEURS_REMBOURSES_SUR_SOLDE.includes(commande.get('fournisseur'))) return false;
    if (commande.get('statut') === 'remboursee') return true;
    const clientId = commande.get('clientId') as string;
    const prixFcfa = commande.get('prixFcfa') as number;
    const portefeuille = await tx.get(refPortefeuille(db, clientId));
    const dejaRendu = await tx.get(refPortefeuille(db, clientId).collection('mouvements').doc(`remboursement_${refCommande.id}`));
    if (!dejaRendu.exists) {
      ecrireMouvement(
        tx,
        db,
        clientId,
        solde(portefeuille),
        {
          id: `remboursement_${refCommande.id}`,
          type: TYPES_MOUVEMENT.remboursement,
          montantFcfa: prixFcfa,
          reference: refCommande.id,
          note: motif,
        },
        maintenant,
      );
    }
    tx.update(refCommande, {
      statut: 'remboursee',
      motifRemboursement: motif,
      rembourseSurSolde: true,
      rembourseeLe: Timestamp.fromDate(maintenant),
    });
    return true;
  });
}
