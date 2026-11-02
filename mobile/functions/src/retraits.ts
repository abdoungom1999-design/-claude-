import { randomBytes } from 'node:crypto';
import { Timestamp, type DocumentReference, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { verifierAdmin } from './admin';
import { FOURNISSEUR_ORANGE } from './fournisseurs';
import { ENVIRONNEMENT_ORANGE_MONEY } from './methodes_paiement';
import { pousser, type Messagerie } from './notifications';
import { ecrireMouvement, objet, refPortefeuille, solde, TYPES_MOUVEMENT } from './portefeuille';
import { prevenirAdmins } from './sauvegardes';

/**
 * Retrait du solde Sprint (lot B ; préparé, puis ouvert avec le go du client
 * du 2 novembre 2026) : le client demande que son solde lui soit envoyé sur
 * Orange Money ou Wave ; le montant est retiré du solde AUSSITÔT (réservé :
 * jamais dépensé deux fois) ; un Admin fait le transfert depuis le compte de
 * Groupe Santine sous 48 h, frais de l'opérateur déduits (payés par le
 * client), puis marque la demande « versée » ; ou il la refuse (motivé) et
 * le montant revient sur le solde. Tout est journalisé.
 *
 *   infosRetrait (client) ──> ce qui peut être retiré maintenant.
 *   demanderRetrait (client) ──> retraits/{id} « demande » + mouvement
 *       « retrait » (débit) ; Admins prévenus.
 *   traiterRetrait (Admin) ──> « verse » (frais, montant envoyé ; rien ne
 *       bouge sur le solde) ou « refuse » + mouvement « retrait_rendu »
 *       (crédit) ; client prévenu.
 *
 * Seul l'argent réellement encaissé par Sprint se retire (voir
 * [montantRetirable]) : tant que Wave est simulé, une recharge Wave ne crée
 * que de l'argent de test, qui paie des courses mais ne devient jamais de
 * l'argent réel.
 */

/**
 * Ouverture des retraits aux clients. Ne change qu'avec le go du client, en
 * même temps que son jumeau dans l'app (`retraitsOuverts`,
 * lib/features/portefeuille/data/retraits.dart) : un test vérifie qu'ils
 * sont d'accord. Fermé : aucune nouvelle demande (le traitement par l'Admin
 * des demandes déjà faites reste possible).
 */
export const RETRAITS_OUVERTS: boolean = true;

export const RETRAIT_MIN_FCFA = 500;

/** Plafond par client et par jour (décision du client, 2 novembre 2026), demandes refusées exclues. */
export const RETRAIT_MAX_JOUR_FCFA = 50_000;

/** Délai annoncé au client pour l'envoi (décision du client, 2 novembre 2026). */
export const DELAI_VERSEMENT_HEURES = 48;

/**
 * Orange Money encaisse de l'argent réel depuis la publication 114 (fonctions
 * déployées le 2 novembre 2026 entre 9 h 41 et 9 h 43, heure de Dakar = UTC) ;
 * avant : bac à sable, argent de test.
 */
export const DEBUT_ARGENT_REEL_ORANGE = new Date('2026-11-02T09:43:00Z');

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

/** Jour de Dakar (UTC toute l'année) : « 2026-11-02 ». Le plafond se compte de minuit à minuit. */
export const jourDakar = (d: Date) => d.toISOString().slice(0, 10);

/**
 * Frais de transfert acceptés au versement : au plus 10 % du montant (100 FCFA
 * au moins), toujours moins que le montant. Au-delà : faute de frappe
 * probable, le client ne doit pas la payer.
 */
export const fraisMaxFcfa = (montant: number) => Math.min(montant - 1, Math.max(Math.floor(montant / 10), 100));

/** Nom affiché à l'Admin : texte du profil, tronqué ; « Client » à défaut. */
const nomClient = (nom: unknown) => (typeof nom === 'string' && nom.trim() ? nom.trim().slice(0, 80) : 'Client');

const formaterFcfa = (montant: number) => `${montant.toLocaleString('fr-FR').replace(/[\u202F\u00A0]/g, ' ')} FCFA`;

/**
 * Argent réellement encaissé par Sprint pour une recharge ou une commande :
 * vrai Wave (`wave`, pas encore branché), ou Orange Money en production
 * (depuis [DEBUT_ARGENT_REEL_ORANGE]). Le faux Wave (`simulation`) et le bac à
 * sable d'Orange Money ne sont que de l'argent de test.
 */
export function encaissementReel(fournisseur: unknown, creeLe: Date | null): boolean {
  if (fournisseur === 'wave') return true;
  return (
    fournisseur === FOURNISSEUR_ORANGE &&
    ENVIRONNEMENT_ORANGE_MONEY === 'production' &&
    creeLe !== null &&
    creeLe.getTime() >= DEBUT_ARGENT_REEL_ORANGE.getTime()
  );
}

const date = (v: unknown) => (v instanceof Timestamp ? v.toDate() : null);

/**
 * Part du solde qui peut être retirée : l'argent réel entré (recharges et
 * remboursements de paiements réellement encaissés), moins les courses payées
 * avec le solde (comptées d'abord sur l'argent réel, par prudence), les
 * retraits et les ajustements négatifs de l'Admin ; jamais plus que le solde.
 * Un remboursement de course payée avec le solde annule son débit ; un
 * ajustement positif de l'Admin (geste commercial) ne se retire pas. Lu dans
 * la transaction de la demande : le livre et le solde sont cohérents.
 */
export async function montantRetirable(tx: Transaction, db: Firestore, uid: string, soldeFcfa: number): Promise<number> {
  const mouvements = (await tx.get(refPortefeuille(db, uid).collection('mouvements'))).docs;
  const sources: DocumentReference[] = [];
  for (const m of mouvements) {
    const reference = m.get('reference');
    if (typeof reference !== 'string' || reference.length === 0 || reference.includes('/')) continue;
    if (m.get('type') === TYPES_MOUVEMENT.recharge) sources.push(db.collection('recharges').doc(reference));
    if (m.get('type') === TYPES_MOUVEMENT.remboursement) sources.push(db.collection('commandes').doc(reference));
  }
  const lues = sources.length > 0 ? await tx.getAll(...sources) : [];
  const reel = new Map<string, boolean>();
  for (const s of lues) {
    reel.set(s.ref.path, s.exists && encaissementReel(s.get('fournisseur'), date(s.get('creeLe'))));
  }
  const fournisseurDe = new Map(lues.map((s) => [s.ref.path, s.exists ? s.get('fournisseur') : undefined]));

  let retirable = 0;
  for (const m of mouvements) {
    const montant = m.get('montantFcfa');
    if (typeof montant !== 'number' || !Number.isFinite(montant)) continue;
    const reference = m.get('reference');
    switch (m.get('type')) {
      case TYPES_MOUVEMENT.recharge:
        if (reel.get(`recharges/${reference}`) === true) retirable += montant;
        break;
      case TYPES_MOUVEMENT.remboursement: {
        const chemin = `commandes/${reference}`;
        // Course payée avec le solde : son débit est annulé. Paiement réel
        // (Orange Money en production) : argent réel rendu.
        if (fournisseurDe.get(chemin) === 'portefeuille' || reel.get(chemin) === true) retirable += montant;
        break;
      }
      case TYPES_MOUVEMENT.ajustementAdmin:
        retirable += Math.min(0, montant);
        break;
      default:
        // Courses payées, retraits (débits) ; retraits refusés (crédits rendus).
        if (
          montant < 0 ||
          m.get('type') === TYPES_MOUVEMENT.retraitRendu
        ) {
          retirable += montant;
        }
    }
  }
  return Math.max(0, Math.min(soldeFcfa, retirable));
}

/** Retraits du client ce jour-là (refusés exclus : leur montant est revenu sur le solde). */
async function retireLeJour(tx: Transaction, db: Firestore, uid: string, jour: string): Promise<number> {
  const duJour = await tx.get(db.collection('retraits').where('clientId', '==', uid).where('jour', '==', jour));
  return duJour.docs.reduce(
    (total, d) => (d.get('statut') === STATUTS_RETRAIT.refuse ? total : total + ((d.get('montantFcfa') as number) || 0)),
    0,
  );
}

/** Compte client actif, sinon refus. */
async function verifierClient(db: Firestore, uid: string | undefined) {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous pour retirer votre solde.');
  const profil = await db.collection('users').doc(uid).get();
  if (!profil.exists || profil.get('role') !== 'client') throw new HttpsError('permission-denied', 'Réservé aux comptes clients.');
  const statutCompte = profil.get('statutCompte');
  if (statutCompte === 'suspendu' || statutCompte === 'banni') {
    throw new HttpsError('permission-denied', 'Votre compte ne permet pas de retirer votre solde. Contactez le support.');
  }
  return { uid, profil };
}

export interface InfosRetrait {
  soldeFcfa: number;
  /** Argent réel du solde, au plus le solde. */
  retirableFcfa: number;
  /** Ce qui reste du plafond du jour. */
  resteDuJourFcfa: number;
  /** Retrait en attente d'envoi (un seul à la fois). */
  enCours: boolean;
  /** Ce qui peut être demandé maintenant (0 : rien). */
  maximumFcfa: number;
}

/** Lecture de [InfosRetrait] dans une transaction (aussi utilisée par la demande). */
async function lireInfos(tx: Transaction, db: Firestore, uid: string, maintenant: Date) {
  const enCours = await tx.get(
    db.collection('retraits').where('clientId', '==', uid).where('statut', '==', STATUTS_RETRAIT.demande).limit(1),
  );
  const dejaRetire = await retireLeJour(tx, db, uid, jourDakar(maintenant));
  const soldeFcfa = solde(await tx.get(refPortefeuille(db, uid)));
  const retirableFcfa = await montantRetirable(tx, db, uid, soldeFcfa);
  const resteDuJourFcfa = Math.max(0, RETRAIT_MAX_JOUR_FCFA - dejaRetire);
  const infos: InfosRetrait = {
    soldeFcfa,
    retirableFcfa,
    resteDuJourFcfa,
    enCours: !enCours.empty,
    maximumFcfa: enCours.empty ? Math.min(retirableFcfa, resteDuJourFcfa) : 0,
  };
  return infos;
}

/** Callable `infosRetrait` (client) : ce qui peut être retiré maintenant, sans rien écrire. */
export async function infosRetrait(
  db: Firestore,
  uid: string | undefined,
  maintenant: Date,
  ouverts: boolean = RETRAITS_OUVERTS,
): Promise<InfosRetrait & { ouverts: boolean }> {
  const client = await verifierClient(db, uid);
  const infos = await db.runTransaction((tx) => lireInfos(tx, db, client.uid, maintenant), { readOnly: true });
  return { ...infos, ouverts };
}

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
  const { profil } = await verifierClient(db, uid);
  const d = objet(donnees);
  const montant = d.montantFcfa;
  if (typeof montant !== 'number' || !Number.isInteger(montant) || montant < RETRAIT_MIN_FCFA) {
    throw new HttpsError('invalid-argument', `Montant invalide : ${formaterFcfa(RETRAIT_MIN_FCFA)} au moins.`);
  }
  if (montant > RETRAIT_MAX_JOUR_FCFA) {
    throw new HttpsError('invalid-argument', `${formaterFcfa(RETRAIT_MAX_JOUR_FCFA)} au plus par jour.`);
  }
  const moyen = MOYENS_RETRAIT.find((m) => m === d.moyen);
  if (moyen === undefined) throw new HttpsError('invalid-argument', 'Choisissez Orange Money ou Wave.');
  const numero = numeroSenegal(d.numero);
  if (numero === null) throw new HttpsError('invalid-argument', 'Numéro invalide : 9 chiffres, commençant par 70, 75, 76, 77 ou 78.');

  const ref = db.collection('retraits').doc(`rtr_${randomBytes(12).toString('hex')}`);
  const jour = jourDakar(maintenant);
  const soldeFcfa = await db.runTransaction(async (tx) => {
    const infos = await lireInfos(tx, db, uid, maintenant);
    if (infos.enCours) {
      throw new HttpsError('failed-precondition', 'Un retrait est déjà en cours de traitement : attendez son envoi.');
    }
    if (montant > infos.soldeFcfa) {
      throw new HttpsError('failed-precondition', `Solde insuffisant : ${formaterFcfa(infos.soldeFcfa)} disponibles.`);
    }
    if (montant > infos.resteDuJourFcfa) {
      throw new HttpsError(
        'failed-precondition',
        infos.resteDuJourFcfa < RETRAIT_MIN_FCFA
          ? `Plafond de ${formaterFcfa(RETRAIT_MAX_JOUR_FCFA)} de retraits par jour atteint : réessayez demain.`
          : `Plafond de ${formaterFcfa(RETRAIT_MAX_JOUR_FCFA)} de retraits par jour : vous pouvez encore retirer ` +
              `${formaterFcfa(infos.resteDuJourFcfa)} aujourd'hui.`,
        { raison: 'plafond_jour', resteDuJourFcfa: infos.resteDuJourFcfa },
      );
    }
    if (montant > infos.retirableFcfa) {
      throw new HttpsError(
        'failed-precondition',
        infos.retirableFcfa < RETRAIT_MIN_FCFA
          ? 'Seul l\'argent réellement payé (Orange Money) peut être retiré ; votre solde vient de recharges en mode ' +
              'test : il sert à payer vos courses.'
          : `Seul l'argent réellement payé (Orange Money) peut être retiré : ${formaterFcfa(infos.retirableFcfa)} au plus. ` +
              'Le reste de votre solde (mode test) sert à payer vos courses.',
        { raison: 'argent_test', retirableFcfa: infos.retirableFcfa },
      );
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
      jour,
      creeLe: Timestamp.fromDate(maintenant),
      aVerserAvant: Timestamp.fromDate(new Date(maintenant.getTime() + DELAI_VERSEMENT_HEURES * 3600_000)),
    });
    return ecrireMouvement(
      tx,
      db,
      uid,
      infos.soldeFcfa,
      { id: `retrait_${ref.id}`, type: TYPES_MOUVEMENT.retrait, montantFcfa: -montant, reference: ref.id, note: LIBELLES_MOYEN[moyen] },
      maintenant,
    );
  });
  await prevenirAdmins(db, messagerie, {
    titre: 'Retrait de solde à verser',
    corps:
      `${formaterFcfa(montant)} à envoyer sur ${LIBELLES_MOYEN[moyen]} sous ${DELAI_VERSEMENT_HEURES} h, ` +
      'frais de transfert déduits. Espace Admin › Finances.',
    canal: 'messages',
    lien: '/#/admin',
    donnees: { type: 'retrait', retraitId: ref.id },
    dureeVieSecondes: 7 * 24 * 60 * 60,
  });
  return { retraitId: ref.id, soldeFcfa };
}

/**
 * Callable `traiterRetrait` (Admin) : { retraitId, decision: 'verse' | 'refuse',
 * fraisFcfa (versé : frais de l'opérateur, déduits du montant envoyé),
 * reference?, motif? (refusé) }.
 */
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
  const frais = d.fraisFcfa;
  if (decision === 'verse' && (typeof frais !== 'number' || !Number.isInteger(frais) || frais < 0)) {
    throw new HttpsError('invalid-argument', 'Indiquez les frais de transfert (0 s\'il n\'y en a pas).');
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
    let fraisFcfa = 0;
    if (decision === 'verse') {
      fraisFcfa = frais as number;
      if (fraisFcfa > fraisMaxFcfa(montant)) {
        throw new HttpsError(
          'invalid-argument',
          `Frais trop élevés : ${formaterFcfa(fraisMaxFcfa(montant))} au plus pour ${formaterFcfa(montant)}. Vérifiez la saisie.`,
        );
      }
      tx.update(ref, {
        statut: STATUTS_RETRAIT.verse,
        ...traitement,
        fraisFcfa,
        montantVerseFcfa: montant - fraisFcfa,
        ...(reference ? { referenceVersement: reference } : {}),
      });
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
    return { clientId, montant, fraisFcfa, moyen: doc.get('moyen') as MoyenRetrait };
  });
  await db.collection('journal_admin').add({
    action: decision === 'verse' ? 'retrait_verse' : 'retrait_refuse',
    adminId,
    clientId: retrait.clientId,
    retraitId,
    montantFcfa: retrait.montant,
    ...(decision === 'verse' ? { fraisFcfa: retrait.fraisFcfa, montantVerseFcfa: retrait.montant - retrait.fraisFcfa } : {}),
    ...(reference ? { reference } : {}),
    ...(motif ? { motif } : {}),
    le: Timestamp.fromDate(maintenant),
  });
  const moyen = LIBELLES_MOYEN[retrait.moyen] ?? 'mobile money';
  const envoye = retrait.montant - retrait.fraisFcfa;
  await pousser(db, messagerie, [retrait.clientId], {
    titre: decision === 'verse' ? 'Retrait envoyé' : 'Retrait refusé',
    corps:
      decision === 'verse'
        ? `${formaterFcfa(envoye)} ont été envoyés sur votre compte ${moyen}` +
          (retrait.fraisFcfa > 0
            ? ` (${formaterFcfa(retrait.montant)} retirés, moins ${formaterFcfa(retrait.fraisFcfa)} de frais de transfert).`
            : '.')
        : `${formaterFcfa(retrait.montant)} sont revenus sur votre solde Sprint. Motif : ${motif}`,
    canal: 'messages',
    lien: '/#/accueil/compte',
    donnees: { type: 'retrait', retraitId },
    dureeVieSecondes: 7 * 24 * 60 * 60,
  });
  return { statut: decision === 'verse' ? STATUTS_RETRAIT.verse : STATUTS_RETRAIT.refuse };
}
