import { randomBytes } from 'node:crypto';
import { Timestamp, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { verifierAdmin } from './admin';
import { pousser, type Messagerie } from './notifications';
import { ecrireMouvement, objet, refPortefeuille, solde, SOLDE_MAX_FCFA, TYPES_MOUVEMENT } from './portefeuille';
import { prevenirAdmins } from './sauvegardes';

/**
 * Retrait du solde Sprint (lot B, préparé le 2 novembre 2026) : le client
 * demande que son solde lui soit renvoyé sur Orange Money ou Wave ; le
 * montant est retiré du solde AUSSITÔT (réservé : jamais dépensé deux fois) ;
 * un Admin fait le transfert depuis le compte de Groupe Santine, puis marque
 * la demande « versée » (avec la référence du transfert), ou la refuse
 * (motivé) et le montant revient sur le solde. Tout est journalisé.
 *
 *   demanderRetrait (client) ──> retraits/{id} « demande » + mouvement
 *       « retrait » (débit) ; Admins prévenus.
 *   traiterRetrait (Admin) ──> « verse » (rien ne bouge sur le solde) ou
 *       « refuse » + mouvement « retrait_rendu » (crédit) ; client prévenu.
 */

/**
 * Ouverture des retraits aux clients. Ne change qu'avec le go du client, en
 * même temps que son jumeau dans l'app (`retraitsOuverts`,
 * lib/features/portefeuille/data/retraits.dart) : un test vérifie qu'ils
 * sont d'accord. Fermé : aucune nouvelle demande (le traitement par l'Admin
 * des demandes déjà faites reste possible).
 */
export const RETRAITS_OUVERTS: boolean = false;

export const RETRAIT_MIN_FCFA = 500;

/** Une demande à la fois par client : la suivante après le traitement de la première. */
export const MOYENS_RETRAIT = ['ORANGE_MONEY', 'WAVE'] as const;
export type MoyenRetrait = (typeof MOYENS_RETRAIT)[number];

export const STATUTS_RETRAIT = { demande: 'demande', verse: 'verse', refuse: 'refuse' } as const;

const LIBELLES_MOYEN: Record<MoyenRetrait, string> = { ORANGE_MONEY: 'Orange Money', WAVE: 'Wave' };

/**
 * Numéro mobile sénégalais, 9 chiffres (70, 75, 76, 77, 78), sans indicatif ;
 * accepte « +221 », « 00221 », espaces, points et tirets. `null` sinon.
 */
export function numeroSenegal(valeur: unknown): string | null {
  if (typeof valeur !== 'string') return null;
  let n = valeur.replace(/[\s.-]/g, '');
  if (n.startsWith('+221')) n = n.slice(4);
  else if (n.startsWith('00221')) n = n.slice(5);
  else if (n.length === 12 && n.startsWith('221')) n = n.slice(3);
  return /^7[05678]\d{7}$/.test(n) ? n : null;
}

/** Nom affiché à l'Admin : texte du profil, tronqué ; « Client » à défaut. */
const nomClient = (nom: unknown) => (typeof nom === 'string' && nom.trim() ? nom.trim().slice(0, 80) : 'Client');

const formaterFcfa = (montant: number) => `${montant.toLocaleString('fr-FR').replace(/ | /g, ' ')} FCFA`;

/** Callable `demanderRetrait` : { montantFcfa, moyen, numero }. */
export async function demanderRetrait(
  db: Firestore,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
  messagerie?: Messagerie,
  ouverts: boolean = RETRAITS_OUVERTS,
): Promise<{ retraitId: string; soldeFcfa: number }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous pour retirer votre solde.');
  if (!ouverts) {
    throw new HttpsError('failed-precondition', "Le retrait du solde n'est pas encore disponible.", { raison: 'retraits_fermes' });
  }
  const profil = await db.collection('users').doc(uid).get();
  if (!profil.exists || profil.get('role') !== 'client') throw new HttpsError('permission-denied', 'Réservé aux comptes clients.');
  const statutCompte = profil.get('statutCompte');
  if (statutCompte === 'suspendu' || statutCompte === 'banni') {
    throw new HttpsError('permission-denied', 'Votre compte ne permet pas de retirer votre solde. Contactez le support.');
  }
  const d = objet(donnees);
  const montant = d.montantFcfa;
  if (typeof montant !== 'number' || !Number.isInteger(montant) || montant < RETRAIT_MIN_FCFA || montant > SOLDE_MAX_FCFA) {
    throw new HttpsError('invalid-argument', `Montant invalide : ${formaterFcfa(RETRAIT_MIN_FCFA)} au moins.`);
  }
  const moyen = MOYENS_RETRAIT.find((m) => m === d.moyen);
  if (moyen === undefined) throw new HttpsError('invalid-argument', 'Choisissez Orange Money ou Wave.');
  const numero = numeroSenegal(d.numero);
  if (numero === null) throw new HttpsError('invalid-argument', 'Numéro invalide : 9 chiffres, commençant par 70, 75, 76, 77 ou 78.');

  const ref = db.collection('retraits').doc(`rtr_${randomBytes(12).toString('hex')}`);
  const soldeFcfa = await db.runTransaction(async (tx) => {
    const enCours = await tx.get(
      db.collection('retraits').where('clientId', '==', uid).where('statut', '==', STATUTS_RETRAIT.demande).limit(1),
    );
    const portefeuille = await tx.get(refPortefeuille(db, uid));
    if (!enCours.empty) {
      throw new HttpsError('failed-precondition', 'Un retrait est déjà en cours de traitement : attendez son versement.');
    }
    const soldeAvant = solde(portefeuille);
    if (montant > soldeAvant) {
      throw new HttpsError('failed-precondition', `Solde insuffisant : ${formaterFcfa(soldeAvant)} disponibles.`);
    }
    tx.create(ref, {
      clientId: uid,
      // Pour l'Admin, qui vérifie avant de verser : nom du compte, et si le
      // numéro de réception est celui du compte (sinon, prudence : compte
      // peut-être utilisé par un autre).
      nomClient: nomClient(profil.get('nom')),
      numeroDuCompte: numeroSenegal(profil.get('telephone')) === numero,
      montantFcfa: montant,
      moyen,
      numero,
      statut: STATUTS_RETRAIT.demande,
      creeLe: Timestamp.fromDate(maintenant),
    });
    return ecrireMouvement(
      tx,
      db,
      uid,
      soldeAvant,
      { id: `retrait_${ref.id}`, type: TYPES_MOUVEMENT.retrait, montantFcfa: -montant, reference: ref.id, note: LIBELLES_MOYEN[moyen] },
      maintenant,
    );
  });
  await prevenirAdmins(db, messagerie, {
    titre: 'Retrait de solde à verser',
    corps: `${formaterFcfa(montant)} à envoyer sur ${LIBELLES_MOYEN[moyen]}. Espace Admin › Finances.`,
    canal: 'messages',
    lien: '/#/admin',
    donnees: { type: 'retrait', retraitId: ref.id },
    dureeVieSecondes: 7 * 24 * 60 * 60,
  });
  return { retraitId: ref.id, soldeFcfa };
}

/** Callable `traiterRetrait` (Admin) : { retraitId, decision: 'verse' | 'refuse', reference?, motif? }. */
export async function traiterRetrait(
  db: Firestore,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
  messagerie?: Messagerie,
): Promise<{ statut: string }> {
  const adminId = await verifierAdmin(db, uid);
  const d = objet(donnees);
  const retraitId = d.retraitId;
  if (typeof retraitId !== 'string' || !/^rtr_[0-9a-f]{24}$/.test(retraitId)) throw new HttpsError('invalid-argument', 'Retrait invalide.');
  const decision = d.decision;
  if (decision !== 'verse' && decision !== 'refuse') throw new HttpsError('invalid-argument', 'Décision invalide.');
  const texte = (v: unknown) => (typeof v === 'string' ? v.trim() : '');
  const reference = texte(d.reference);
  const motif = texte(d.motif);
  if (reference.length > 100) throw new HttpsError('invalid-argument', 'Référence du transfert trop longue (100 caractères au plus).');
  if (decision === 'refuse' && (motif.length === 0 || motif.length > 300)) {
    throw new HttpsError('invalid-argument', 'Indiquez le motif du refus (300 caractères au plus).');
  }

  const ref = db.collection('retraits').doc(retraitId);
  const retrait = await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists) throw new HttpsError('not-found', 'Retrait introuvable.');
    if (doc.get('statut') !== STATUTS_RETRAIT.demande) throw new HttpsError('failed-precondition', 'Ce retrait a déjà été traité.');
    const clientId = doc.get('clientId') as string;
    const montant = doc.get('montantFcfa') as number;
    const portefeuille = await tx.get(refPortefeuille(db, clientId));
    const traitement = { traiteLe: Timestamp.fromDate(maintenant), traitePar: adminId };
    if (decision === 'verse') {
      tx.update(ref, { statut: STATUTS_RETRAIT.verse, ...traitement, ...(reference ? { referenceVersement: reference } : {}) });
    } else {
      tx.update(ref, { statut: STATUTS_RETRAIT.refuse, ...traitement, motifRefus: motif });
      ecrireMouvement(
        tx,
        db,
        clientId,
        solde(portefeuille),
        { id: `retrait_rendu_${retraitId}`, type: TYPES_MOUVEMENT.retraitRendu, montantFcfa: montant, reference: retraitId, note: motif },
        maintenant,
      );
    }
    return { clientId, montant, moyen: doc.get('moyen') as MoyenRetrait };
  });
  await db.collection('journal_admin').add({
    action: decision === 'verse' ? 'retrait_verse' : 'retrait_refuse',
    adminId,
    clientId: retrait.clientId,
    retraitId,
    montantFcfa: retrait.montant,
    ...(reference ? { reference } : {}),
    ...(motif ? { motif } : {}),
    le: Timestamp.fromDate(maintenant),
  });
  const moyen = LIBELLES_MOYEN[retrait.moyen] ?? 'mobile money';
  await pousser(db, messagerie, [retrait.clientId], {
    titre: decision === 'verse' ? 'Retrait versé' : 'Retrait refusé',
    corps:
      decision === 'verse'
        ? `${formaterFcfa(retrait.montant)} ont été envoyés sur votre compte ${moyen}.`
        : `${formaterFcfa(retrait.montant)} sont revenus sur votre solde Sprint. Motif : ${motif}`,
    canal: 'messages',
    lien: '/#/accueil/compte',
    donnees: { type: 'retrait', retraitId },
    dureeVieSecondes: 7 * 24 * 60 * 60,
  });
  return { statut: decision === 'verse' ? STATUTS_RETRAIT.verse : STATUTS_RETRAIT.refuse };
}
