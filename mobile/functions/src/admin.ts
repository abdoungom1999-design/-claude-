import { randomBytes } from 'node:crypto';
import { FieldValue, Timestamp, type DocumentSnapshot, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import type { FournisseurPaiement } from './fournisseurs';
import { rembourserCommande, STATUTS_COMMANDE } from './paiements';
import { ecrireMouvement, refPortefeuille, SOLDE_MAX_FCFA, solde, TYPES_MOUVEMENT } from './portefeuille';

/**
 * Actions de l'Admin qui touchent à l'argent ou aux comptes : passées
 * par le serveur pour être complètes (annulation + remboursement) et
 * tracées dans `journal_admin` (qui, quand, quoi), jamais modifiable
 * depuis l'app.
 */

export const STATUTS_COMPTE = ['actif', 'suspendu', 'banni'] as const;
type StatutCompte = (typeof STATUTS_COMPTE)[number];

/** Courses qu'un chauffeur sanctionné ne peut pas terminer. */
const STATUTS_COURSE_ACTIVE = ['acceptee', 'en_cours'];

function donneesObjet(donnees: unknown): Record<string, unknown> {
  return (typeof donnees === 'object' && donnees !== null ? donnees : {}) as Record<string, unknown>;
}

function identifiant(valeur: unknown, nom: string): string {
  if (typeof valeur !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(valeur)) {
    throw new HttpsError('invalid-argument', `${nom} invalide.`);
  }
  return valeur;
}

function motif(valeur: unknown, obligatoire: boolean): string | null {
  if (valeur === undefined || valeur === null || valeur === '') {
    if (obligatoire) throw new HttpsError('invalid-argument', 'Indiquez le motif.');
    return null;
  }
  if (typeof valeur !== 'string' || valeur.trim().length === 0 || valeur.length > 300) {
    throw new HttpsError('invalid-argument', 'Motif invalide (300 caractères au plus).');
  }
  return valeur.trim();
}

/** Appelant connecté avec le rôle admin (posé depuis la Console seulement). */
export async function verifierAdmin(db: Firestore, uid: string | undefined): Promise<string> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous.');
  const profil = await db.collection('users').doc(uid).get();
  if (profil.get('role') !== 'admin') throw new HttpsError('permission-denied', 'Réservé à l\'Admin.');
  return uid;
}

async function journaliser(db: Firestore, entree: Record<string, unknown>, maintenant: Date): Promise<void> {
  await db.collection('journal_admin').add({ ...entree, le: Timestamp.fromDate(maintenant) });
}

/**
 * Message automatique dans le ticket de la course, s'il existe (le client
 * le voit dans sa conversation avec le support).
 */
async function informerTicket(db: Firestore, courseId: string, texte: string, maintenant: Date): Promise<void> {
  const ticket = db.collection('tickets').doc(courseId);
  if (!(await ticket.get()).exists) return;
  const batch = db.batch();
  batch.create(ticket.collection('messages').doc(), {
    auteurId: 'systeme',
    auteurRole: 'systeme',
    texte,
    creeLe: Timestamp.fromDate(maintenant),
  });
  batch.update(ticket, {
    dernierMessage: texte.slice(0, 200),
    majLe: Timestamp.fromDate(maintenant),
    nonLuClient: true,
  });
  await batch.commit();
}

// ---------------------------------------------------------------------
// Remboursement intégral d'une course (callable `rembourserCourseAdmin`)
// ---------------------------------------------------------------------

export interface RemboursementAdmin {
  rembourse: boolean;
  montantFcfa: number;
  /** Part du chauffeur (85 %) retirée de ce que Sprint lui doit. */
  partChauffeurRetireeFcfa: number;
}

/** Commission de la plateforme : 15 % du prix, arrondi à l'inférieur (comme l'app et les règles). */
const POURCENTAGE_COMMISSION = 15;

/**
 * Part du chauffeur sur une course terminée : le prix moins la
 * commission figée à l'arrivée (même formule pour les courses plus
 * anciennes). Aucune part sur une course annulée.
 */
function partChauffeur(course: DocumentSnapshot): number {
  if (course.get('statut') !== 'terminee' || typeof course.get('chauffeurId') !== 'string') return 0;
  const prix = course.get('prixFcfa') as number;
  const commission = course.get('commissionFcfa');
  return prix - (typeof commission === 'number' ? commission : Math.floor((prix * POURCENTAGE_COMMISSION) / 100));
}

/**
 * Rembourse intégralement au client une course terminée ou annulée (par
 * exemple après un ticket support), via le fournisseur de paiement. Une
 * course encore en cours doit d'abord être annulée. En cas de refus du
 * fournisseur, la commande passe en `remboursement_echoue` (visible) et
 * l'Admin peut réessayer.
 *
 * Sur une course terminée, le chauffeur n'est pas payé pour une course
 * remboursée : sa part (85 %) sort de ce que Sprint lui doit (l'app
 * ignore dans les comptes toute course portant `rembourseeLe`). Si elle
 * lui a déjà été versée, elle est déduite de ses prochains gains.
 */
export async function rembourserCourseAdmin(
  db: Firestore,
  fournisseur: FournisseurPaiement,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
): Promise<RemboursementAdmin> {
  const adminId = await verifierAdmin(db, uid);
  const d = donneesObjet(donnees);
  const courseId = identifiant(d.courseId, 'Course');
  const raison = motif(d.motif, true)!;

  const refCourse = db.collection('courses').doc(courseId);
  const course = await refCourse.get();
  if (!course.exists) throw new HttpsError('not-found', 'Course introuvable.');
  const statut = course.get('statut');
  if (statut !== 'terminee' && statut !== 'annulee') {
    throw new HttpsError('failed-precondition', 'Course en cours : elle doit être terminée ou annulée avant un remboursement.');
  }
  const commandeId = course.get('commandeId');
  if (typeof commandeId !== 'string') {
    throw new HttpsError('failed-precondition', 'Course payée avant le paiement par le serveur : remboursement à faire à la main.');
  }
  const refCommande = db.collection('commandes').doc(commandeId);
  const commande = await refCommande.get();
  if (commande.get('statut') === STATUTS_COMMANDE.remboursee) {
    throw new HttpsError('already-exists', 'Cette course a déjà été remboursée.');
  }
  const montantFcfa = commande.get('prixFcfa') as number;

  const partRetiree = partChauffeur(course);

  const rembourse = await rembourserCommande(db, fournisseur, refCommande, 'support_admin', maintenant);
  if (rembourse) {
    await refCourse.update({
      rembourseeLe: Timestamp.fromDate(maintenant),
      rembourseePar: adminId,
      partChauffeurRetireeFcfa: partRetiree,
    });
    await informerTicket(
      db,
      courseId,
      commande.get('fournisseur') === 'portefeuille'
        ? `Votre course a été remboursée intégralement (${montantFcfa} FCFA) sur votre portefeuille Sprint.`
        : `Votre course a été remboursée intégralement (${montantFcfa} FCFA) sur votre compte mobile money.`,
      maintenant,
    );
  }
  await journaliser(db, {
    action: 'remboursement',
    adminId,
    courseId,
    commandeId,
    montantFcfa,
    chauffeurId: course.get('chauffeurId') ?? null,
    partChauffeurRetireeFcfa: rembourse ? partRetiree : 0,
    motif: raison,
    resultat: rembourse ? 'rembourse' : 'echec_fournisseur',
  }, maintenant);
  return { rembourse, montantFcfa, partChauffeurRetireeFcfa: rembourse ? partRetiree : 0 };
}

// ---------------------------------------------------------------------
// Suspension, bannissement, réactivation (callable `sanctionnerCompte`)
// ---------------------------------------------------------------------

export interface Sanction {
  statutCompte: StatutCompte;
  coursesAnnulees: number;
  remboursements: number;
}

/**
 * Change le statut d'un compte. Suspendre ou bannir un chauffeur annule
 * aussi sa course en cours (le client est remboursé), le retire de la
 * carte en direct et le rend indisponible ; le chauffeur connecté est
 * éjecté en direct par l'app. Le motif est obligatoire pour sanctionner.
 */
export async function sanctionnerCompte(
  db: Firestore,
  fournisseur: FournisseurPaiement,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
): Promise<Sanction> {
  const adminId = await verifierAdmin(db, uid);
  const d = donneesObjet(donnees);
  const cible = identifiant(d.uid, 'Compte');
  const statutCompte = d.statutCompte as StatutCompte;
  if (!STATUTS_COMPTE.includes(statutCompte)) throw new HttpsError('invalid-argument', 'Statut de compte invalide.');
  const bloque = statutCompte !== 'actif';
  const raison = motif(d.motif, bloque);
  if (cible === adminId) throw new HttpsError('failed-precondition', 'Vous ne pouvez pas vous sanctionner vous-même.');

  const refCompte = db.collection('users').doc(cible);
  const compte = await refCompte.get();
  if (!compte.exists) throw new HttpsError('not-found', 'Compte introuvable.');
  const role = compte.get('role');
  if (role === 'admin') throw new HttpsError('permission-denied', 'Un compte Admin ne peut pas être sanctionné ici.');

  await refCompte.update({
    statutCompte,
    motifSanction: bloque ? raison : FieldValue.delete(),
    sanctionneLe: Timestamp.fromDate(maintenant),
    sanctionnePar: adminId,
  });

  let coursesAnnulees = 0;
  let remboursements = 0;
  if (role === 'conducteur') {
    // Disponibilité publique alignée (même règle que l'app Admin).
    await db.collection('profils_publics').doc(cible).set(
      { disponible: !bloque && compte.get('statutValidation') === 'valide' },
      { merge: true },
    );
    if (bloque) {
      await db.collection('positions_chauffeurs').doc(cible).delete();
      // Deux filtres d'égalité : pas d'index composite nécessaire.
      const actives = await db.collection('courses')
        .where('chauffeurId', '==', cible)
        .where('statut', 'in', STATUTS_COURSE_ACTIVE)
        .get();
      for (const doc of actives.docs) {
        if (!STATUTS_COURSE_ACTIVE.includes(doc.get('statut'))) continue;
        const annulee = await db.runTransaction(async (tx) => {
          const actuelle = await tx.get(doc.ref);
          if (!STATUTS_COURSE_ACTIVE.includes(actuelle.get('statut'))) return false;
          tx.update(doc.ref, {
            statut: 'annulee',
            annuleePar: 'systeme',
            motifAnnulation: 'chauffeur_suspendu',
            annuleeLe: Timestamp.fromDate(maintenant),
          });
          return true;
        });
        if (!annulee) continue;
        coursesAnnulees++;
        const commandeId = doc.get('commandeId');
        if (typeof commandeId === 'string') {
          const ok = await rembourserCommande(db, fournisseur, db.collection('commandes').doc(commandeId), 'chauffeur_suspendu', maintenant);
          if (ok) remboursements++;
        }
      }
    }
  }

  await journaliser(db, {
    action: 'sanction',
    adminId,
    cible,
    role,
    statutCompte,
    motif: raison,
    coursesAnnulees,
    remboursements,
  }, maintenant);
  return { statutCompte, coursesAnnulees, remboursements };
}

// ---------------------------------------------------------------------
// 5. Ajustement manuel par l'Admin (callable `ajusterPortefeuille`)
// ---------------------------------------------------------------------

/**
 * Crédit ou débit manuel, motivé, tracé dans le livre et dans le journal
 * Admin (geste commercial, correction d'erreur, recharge non créditée à
 * régulariser). Le solde ne peut ni devenir négatif ni dépasser le plafond.
 */
export async function ajusterPortefeuille(
  db: Firestore,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
): Promise<{ soldeFcfa: number }> {
  const adminId = await verifierAdmin(db, uid);
  const d = donneesObjet(donnees);
  const clientId = d.clientId;
  if (typeof clientId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(clientId)) {
    throw new HttpsError('invalid-argument', 'Client invalide.');
  }
  const montant = d.montantFcfa;
  if (typeof montant !== 'number' || !Number.isInteger(montant) || montant === 0 || Math.abs(montant) > SOLDE_MAX_FCFA) {
    throw new HttpsError('invalid-argument', 'Montant invalide (entier non nul).');
  }
  const motif = typeof d.motif === 'string' ? d.motif.trim() : '';
  if (motif.length === 0 || motif.length > 300) {
    throw new HttpsError('invalid-argument', 'Indiquez le motif (300 caractères au plus).');
  }
  const client = await db.collection('users').doc(clientId).get();
  if (!client.exists || client.get('role') !== 'client') throw new HttpsError('not-found', 'Client introuvable.');

  const soldeFcfa = await db.runTransaction(async (tx) => {
    const portefeuille = await tx.get(refPortefeuille(db, clientId));
    const soldeAvant = solde(portefeuille);
    if (soldeAvant + montant < 0) {
      throw new HttpsError('failed-precondition', 'Le solde ne peut pas devenir négatif.');
    }
    if (soldeAvant + montant > SOLDE_MAX_FCFA) {
      throw new HttpsError('failed-precondition', `Le solde ne peut pas dépasser ${SOLDE_MAX_FCFA} FCFA.`);
    }
    return ecrireMouvement(
      tx,
      db,
      clientId,
      soldeAvant,
      {
        id: `ajustement_${randomBytes(8).toString('hex')}`,
        type: TYPES_MOUVEMENT.ajustementAdmin,
        montantFcfa: montant,
        reference: null,
        note: motif,
      },
      maintenant,
    );
  });
  await db.collection('journal_admin').add({
    action: 'ajustement_portefeuille',
    adminId,
    clientId,
    montantFcfa: montant,
    motif,
    soldeApresFcfa: soldeFcfa,
    le: Timestamp.fromDate(maintenant),
  });
  return { soldeFcfa };
}
