import { randomBytes } from 'node:crypto';
import { FieldValue, Timestamp, type DocumentReference, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';
import { prixServeur, validerDemande, verifierClient } from './commandes';
import type { CalculDistance } from './distances';
import type { EvenementPaiement, FournisseurPaiement } from './fournisseurs';
import { notifierAnnulation, notifierNouvelleCourse, type Messagerie } from './notifications';

/**
 * Parcours de paiement : aucune course n'existe tant que le fournisseur
 * (Wave, ou le faux Wave en test) n'a pas confirmé le paiement au
 * serveur. L'app ne fait que demander un paiement et suivre la commande.
 *
 *   creerPaiement ──> commande "en_attente_paiement" + lien de paiement
 *   webhook signé ──> commande "payee" + course "en_attente" (chauffeurs)
 *                └──> commande "echouee" (refus, annulation)
 *   surveillance  ──> commande "expiree" si jamais payée ;
 *                     course annulée + remboursement si aucun chauffeur
 *   annulerCourse ──> course annulée + remboursement
 */

export const STATUTS_COMMANDE = {
  enAttente: 'en_attente_paiement',
  payee: 'payee',
  echouee: 'echouee',
  expiree: 'expiree',
  remboursee: 'remboursee',
  remboursementEchoue: 'remboursement_echoue',
  anomalie: 'anomalie',
} as const;

/** Un paiement non finalisé expire au bout de 20 minutes. */
export const DUREE_PAIEMENT_MS = 20 * 60 * 1000;

/** Sans chauffeur au bout de 10 minutes : course annulée et remboursée. */
export const ATTENTE_CHAUFFEUR_MS = 10 * 60 * 1000;

export const MOTIFS_ANNULATION_CHAUFFEUR = ['client_introuvable', 'panne', 'autre'];

// ---------------------------------------------------------------------
// 1. Demande de paiement (callable `creerPaiement`)
// ---------------------------------------------------------------------

export interface PaiementCree {
  commandeId: string;
  lienPaiement: string;
  prixFcfa: number;
}

export async function creerPaiement(
  db: Firestore,
  calcul: CalculDistance,
  fournisseur: FournisseurPaiement,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
): Promise<PaiementCree> {
  // Connexion vérifiée avant tout : un inconnu n'apprend rien de la
  // validation des demandes.
  const clientId = await verifierClient(db, uid);
  const demande = validerDemande(donnees);
  const { estimation, distance } = await prixServeur(calcul, demande, maintenant);

  const ref = db.collection('commandes').doc(randomBytes(12).toString('hex'));
  let session;
  try {
    session = await fournisseur.creerSession(ref.id, estimation.prixFcfa);
  } catch (e) {
    logger.error('Session de paiement impossible', e);
    throw new HttpsError('unavailable', 'Le paiement est momentanément indisponible. Réessayez.');
  }

  await ref.create({
    clientId,
    statut: STATUTS_COMMANDE.enAttente,
    type: demande.type,
    adresseDepart: demande.adresseDepart,
    adresseArrivee: demande.adresseArrivee,
    latitudeDepart: demande.depart.latitude,
    longitudeDepart: demande.depart.longitude,
    latitudeArrivee: demande.arrivee.latitude,
    longitudeArrivee: demande.arrivee.longitude,
    distanceKm: Math.round(distance.distanceKm * 100) / 100,
    sourceDistance: distance.source,
    prixFcfa: estimation.prixFcfa,
    methodePaiement: demande.methodePaiement,
    fournisseur: fournisseur.nom,
    sessionPaiementId: session.sessionId,
    lienPaiement: session.lienPaiement,
    creeLe: Timestamp.fromDate(maintenant),
    expireLe: Timestamp.fromDate(new Date(maintenant.getTime() + DUREE_PAIEMENT_MS)),
  });
  return { commandeId: ref.id, lienPaiement: session.lienPaiement, prixFcfa: estimation.prixFcfa };
}

// ---------------------------------------------------------------------
// 2. Confirmation du fournisseur (fonction HTTP `webhookPaiement`)
// ---------------------------------------------------------------------

export type ResultatWebhook = 'course_creee' | 'deja_traite' | 'echec_enregistre' | 'rembourse' | 'anomalie' | 'inconnue';

/**
 * Traite un événement déjà vérifié (signature) par le fournisseur. Rejouer
 * le même événement ne crée jamais une deuxième course.
 */
export async function traiterEvenement(
  db: Firestore,
  fournisseur: FournisseurPaiement,
  evenement: EvenementPaiement,
  maintenant: Date,
  messagerie?: Messagerie,
): Promise<ResultatWebhook> {
  const refCommande = db.collection('commandes').doc(evenement.commandeId);
  let courseCreeeId: string | undefined;

  const resultat = await db.runTransaction(async (tx): Promise<ResultatWebhook | 'a_rembourser'> => {
    const commande = await tx.get(refCommande);
    if (!commande.exists || commande.get('sessionPaiementId') !== evenement.sessionId) return 'inconnue';
    const statut = commande.get('statut') as string;
    const prixFcfa = commande.get('prixFcfa') as number;

    if (statut !== STATUTS_COMMANDE.enAttente) {
      // Paiement réussi mais commande déjà expirée ou annulée : on rend l'argent.
      if (evenement.reussi && (statut === STATUTS_COMMANDE.expiree || statut === STATUTS_COMMANDE.echouee)) {
        return 'a_rembourser';
      }
      return 'deja_traite';
    }

    if (!evenement.reussi) {
      tx.update(refCommande, { statut: STATUTS_COMMANDE.echouee, termineeLe: Timestamp.fromDate(maintenant) });
      return 'echec_enregistre';
    }

    if (evenement.montantFcfa !== prixFcfa || evenement.devise !== 'XOF') {
      logger.error('Montant payé différent du prix', { commande: refCommande.id, evenement, prixFcfa });
      tx.update(refCommande, { statut: STATUTS_COMMANDE.anomalie, termineeLe: Timestamp.fromDate(maintenant) });
      return 'anomalie';
    }

    const refCourse = db.collection('courses').doc();
    const c = commande.data()!;
    tx.create(refCourse, {
      clientId: c.clientId,
      chauffeurId: null,
      statut: 'en_attente',
      type: c.type,
      adresseDepart: c.adresseDepart,
      adresseArrivee: c.adresseArrivee,
      latitudeDepart: c.latitudeDepart,
      longitudeDepart: c.longitudeDepart,
      latitudeArrivee: c.latitudeArrivee,
      longitudeArrivee: c.longitudeArrivee,
      distanceKm: c.distanceKm,
      sourceDistance: c.sourceDistance,
      prixFcfa,
      methodePaiement: c.methodePaiement,
      transactionId: evenement.sessionId,
      modePaiement: c.fournisseur,
      commandeId: refCommande.id,
      timestamp: FieldValue.serverTimestamp(),
    });
    tx.update(refCommande, {
      statut: STATUTS_COMMANDE.payee,
      courseId: refCourse.id,
      payeeLe: Timestamp.fromDate(maintenant),
    });
    courseCreeeId = refCourse.id;
    return 'course_creee';
  });

  if (resultat === 'a_rembourser') {
    await rembourserCommande(db, fournisseur, refCommande, 'paiement_tardif', maintenant);
    return 'rembourse';
  }
  // Les chauffeurs disponibles sont prévenus (même app fermée). Jamais
  // bloquant : la course existe, le paiement est réglé.
  if (resultat === 'course_creee' && courseCreeeId) await notifierNouvelleCourse(db, messagerie, courseCreeeId);
  return resultat;
}

// ---------------------------------------------------------------------
// 3. Remboursement
// ---------------------------------------------------------------------

/**
 * Rend l'argent d'une commande payée. En cas d'échec chez le
 * fournisseur, la commande passe en "remboursement_echoue" : visible pour
 * un traitement manuel, jamais silencieux.
 */
export async function rembourserCommande(
  db: Firestore,
  fournisseur: FournisseurPaiement,
  refCommande: DocumentReference,
  motif: string,
  maintenant: Date,
): Promise<boolean> {
  const commande = await refCommande.get();
  if (!commande.exists) return false;
  if (commande.get('statut') === STATUTS_COMMANDE.remboursee) return true;
  if (commande.get('fournisseur') !== fournisseur.nom) {
    logger.error('Remboursement : fournisseur différent', { commande: refCommande.id });
    await refCommande.update({ statut: STATUTS_COMMANDE.remboursementEchoue, motifRemboursement: motif });
    return false;
  }
  try {
    await fournisseur.rembourser(commande.get('sessionPaiementId'), commande.get('prixFcfa'));
    await refCommande.update({
      statut: STATUTS_COMMANDE.remboursee,
      motifRemboursement: motif,
      rembourseeLe: Timestamp.fromDate(maintenant),
    });
    return true;
  } catch (e) {
    logger.error('Remboursement impossible', { commande: refCommande.id, erreur: String(e) });
    await refCommande.update({ statut: STATUTS_COMMANDE.remboursementEchoue, motifRemboursement: motif });
    return false;
  }
}

async function rembourserCourse(
  db: Firestore,
  fournisseur: FournisseurPaiement,
  commandeId: unknown,
  motif: string,
  maintenant: Date,
): Promise<boolean> {
  // Courses d'avant le paiement serveur : rien à rembourser.
  if (typeof commandeId !== 'string') return false;
  return rembourserCommande(db, fournisseur, db.collection('commandes').doc(commandeId), motif, maintenant);
}

// ---------------------------------------------------------------------
// 4. Annulation (callable `annulerCourse`)
// ---------------------------------------------------------------------

/**
 * Le client annule sa demande tant qu'aucun chauffeur ne l'a prise ; le
 * chauffeur attribué annule avec un motif. Dans les deux cas, le client
 * est remboursé.
 */
export async function annulerCourse(
  db: Firestore,
  fournisseur: FournisseurPaiement,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
  messagerie?: Messagerie,
): Promise<{ rembourse: boolean }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous pour annuler une course.');
  const d = (typeof donnees === 'object' && donnees !== null ? donnees : {}) as Record<string, unknown>;
  if (typeof d.courseId !== 'string' || !/^[A-Za-z0-9]{1,64}$/.test(d.courseId)) {
    throw new HttpsError('invalid-argument', 'Course invalide.');
  }
  const ref = db.collection('courses').doc(d.courseId);

  let prevenirClient: string | undefined;
  const commandeId = await db.runTransaction(async (tx) => {
    prevenirClient = undefined;
    const course = await tx.get(ref);
    if (!course.exists) throw new HttpsError('not-found', 'Course introuvable.');
    const statut = course.get('statut');

    if (course.get('clientId') === uid) {
      if (statut !== 'en_attente') {
        throw new HttpsError('failed-precondition', 'Un chauffeur a déjà accepté cette course.');
      }
      tx.update(ref, { statut: 'annulee', annuleePar: 'client', annuleeLe: Timestamp.fromDate(maintenant) });
    } else if (course.get('chauffeurId') === uid) {
      if (statut !== 'acceptee' && statut !== 'en_cours') {
        throw new HttpsError('failed-precondition', 'Cette course ne peut plus être annulée.');
      }
      if (!MOTIFS_ANNULATION_CHAUFFEUR.includes(d.motif as string)) {
        throw new HttpsError('invalid-argument', "Motif d'annulation invalide.");
      }
      tx.update(ref, {
        statut: 'annulee',
        annuleePar: 'chauffeur',
        motifAnnulation: d.motif,
        annuleeLe: Timestamp.fromDate(maintenant),
      });
      prevenirClient = course.get('clientId');
    } else {
      throw new HttpsError('permission-denied', 'Cette course ne vous concerne pas.');
    }
    return course.get('commandeId');
  });

  const rembourse = await rembourserCourse(db, fournisseur, commandeId, 'course_annulee', maintenant);
  if (prevenirClient) await notifierAnnulation(db, messagerie, prevenirClient, d.courseId, 'chauffeur');
  return { rembourse };
}

// ---------------------------------------------------------------------
// 5. Surveillance (toutes les 5 minutes)
// ---------------------------------------------------------------------

export async function surveiller(
  db: Firestore,
  fournisseur: FournisseurPaiement,
  maintenant: Date,
  messagerie?: Messagerie,
): Promise<{ expirees: number; sansChauffeur: number }> {
  let expirees = 0;
  const enAttente = await db.collection('commandes').where('statut', '==', STATUTS_COMMANDE.enAttente).get();
  for (const doc of enAttente.docs) {
    const expireLe = doc.get('expireLe') as Timestamp | undefined;
    if (!expireLe || expireLe.toMillis() > maintenant.getTime()) continue;
    const expiree = await db.runTransaction(async (tx) => {
      const actuelle = await tx.get(doc.ref);
      if (actuelle.get('statut') !== STATUTS_COMMANDE.enAttente) return false;
      tx.update(doc.ref, { statut: STATUTS_COMMANDE.expiree, termineeLe: Timestamp.fromDate(maintenant) });
      return true;
    });
    if (expiree) expirees++;
  }

  let sansChauffeur = 0;
  const courses = await db.collection('courses').where('statut', '==', 'en_attente').get();
  for (const doc of courses.docs) {
    const creeLe = doc.get('timestamp') as Timestamp | undefined;
    if (!creeLe || maintenant.getTime() - creeLe.toMillis() < ATTENTE_CHAUFFEUR_MS) continue;
    const annulee = await db.runTransaction(async (tx) => {
      const actuelle = await tx.get(doc.ref);
      if (actuelle.get('statut') !== 'en_attente') return false;
      tx.update(doc.ref, {
        statut: 'annulee',
        annuleePar: 'systeme',
        motifAnnulation: 'aucun_chauffeur',
        annuleeLe: Timestamp.fromDate(maintenant),
      });
      return true;
    });
    if (annulee) {
      sansChauffeur++;
      await rembourserCourse(db, fournisseur, doc.get('commandeId'), 'aucun_chauffeur', maintenant);
      await notifierAnnulation(db, messagerie, doc.get('clientId'), doc.id, 'systeme');
    }
  }
  return { expirees, sansChauffeur };
}
