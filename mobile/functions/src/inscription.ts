import { getAuth } from 'firebase-admin/auth';
import { Timestamp, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';
import { LIENS, pousser, type Messagerie } from './notifications';
import { numeroSenegal } from './retraits';

/**
 * Tunnel d'inscription : double vérification (e-mail, puis numéro de
 * téléphone par SMS) et message « Bienvenue chez SPRINT ».
 *
 * Tout ce fichier est FERMÉ tant que les trois réglages ci-dessous le sont :
 * la publication qui l'apporte ne change rien pour personne (aucun écran, aucun
 * SMS, aucun message). On l'ouvre avec l'accord du client, une fois les
 * réglages de la console faits (voir FIREBASE_SETUP.md, section 13).
 *
 * Ce qui ne change JAMAIS, ouvert ou fermé :
 *   - les comptes existants (créés avant [NOUVEAUX_COMPTES_DEPUIS]) ne sont ni
 *     bloqués, ni sollicités, ni accueillis ;
 *   - rien ici ne touche aux paiements, aux recharges, aux retraits ni aux
 *     comptes de test (aucun de leurs champs n'est lu ou écrit) ;
 *   - le numéro d'un compte reste dans `users/{uid}.telephone` : la validation
 *     ajoute seulement des marques posées par ce serveur (`telephoneVerifie`,
 *     `telephoneValide`, `telephoneVerifieLe`, `bienvenueEnvoyeeLe`), que
 *     l'app ne peut ni créer ni modifier (voir firestore.rules).
 *
 * Comment le numéro est validé. Firebase envoie le SMS et contrôle le code
 * (Firebase Phone Auth), mais un numéro Firebase ne peut appartenir qu'à UN
 * compte, alors que Sprint permet le même numéro à un compte Client et à un
 * compte Chauffeur. L'app fait donc le contrôle sur une session secondaire
 * (qui ne touche pas à la session de l'utilisateur) et nous remet la preuve :
 * le jeton d'identité de cette session « téléphone ». Ce serveur le vérifie
 * (signature Google, fournisseur « phone », fraîcheur), lit le numéro DANS le
 * jeton (jamais dans la demande), le rapproche du numéro du profil, et pose les
 * marques. La session « téléphone » est ensuite supprimée.
 */

export type EtatValidationTelephone = 'fermee' | 'facultative' | 'obligatoire';

/**
 * Validation du numéro par SMS (code à 6 chiffres), pour les NOUVEAUX comptes :
 *   - `fermee` : rien (état de la publication 126) ;
 *   - `facultative` : l'écran est proposé, « Plus tard » le passe ;
 *   - `obligatoire` : l'écran bloque l'espace tant que le numéro n'est pas validé.
 * Même valeur dans l'app (`reglage_inscription.dart`) : un test les compare.
 */
export const VALIDATION_TELEPHONE: EtatValidationTelephone = 'fermee';

/**
 * Message « Bienvenue chez SPRINT » à la fin de l'inscription (écran dans l'app
 * et notification sur les appareils du compte). Fermé : aucun message.
 */
export const BIENVENUE_AUTOMATIQUE: boolean = false;

/**
 * Même message par e-mail, en plus. Il part du domaine officiel via
 * l'extension Firebase « Trigger Email from Firestore » (document dans `mail`),
 * à installer par le client : tant que ce n'est pas fait, laisser à `false`
 * (voir EMAILS_DOMAINE.md).
 */
export const EMAIL_BIENVENUE: boolean = false;

/**
 * Un compte est « nouveau » s'il a été créé (date d'ouverture de son compte
 * Firebase Auth, posée par Google, pas par l'app) à cet instant ou après. Avant
 * l'ouverture du tunnel, la date est lointaine : AUCUN compte n'est nouveau.
 * Même valeur dans l'app.
 */
export const NOUVEAUX_COMPTES_DEPUIS = new Date('2099-01-01T00:00:00Z');

/** Le code vient d'être saisi : au-delà, le jeton ne prouve plus rien (erreur d'horloge tolérée : 2 minutes). */
export const FRAICHEUR_CODE_MS = 10 * 60_000;
const TOLERANCE_HORLOGE_MS = 2 * 60_000;

const LONGUEUR_MAX_JETON = 4096;
const ROLES = ['client', 'conducteur'] as const;

const MESSAGE_CODE_INVALIDE = "Le code n'a pas pu être contrôlé. Demandez un nouveau code.";

/** Numéro mobile sénégalais au format international (« +221771234567 »), `null` s'il n'en est pas un. */
export function telephoneE164(valeur: unknown): string | null {
  const numero = numeroSenegal(valeur);
  return numero === null ? null : `+221${numero}`;
}

// ---------------------------------------------------------------------
// Accès à Firebase Auth (remplaçables dans les tests)
// ---------------------------------------------------------------------

/** Ce que le jeton d'une session « téléphone » prouve. */
export interface PreuveTelephone {
  /** Identifiant de la session « téléphone » (pas celui du compte Sprint). */
  uid: string;
  /** Fournisseur de la connexion : `phone` quand le code SMS a été saisi. */
  fournisseur: string;
  /** Numéro contrôlé par Firebase (« +221… »), s'il y en a un. */
  telephone: string | undefined;
  /** Instant de la saisie du code. */
  connecteLe: Date | undefined;
}
export type VerifierJetonTelephone = (jeton: string) => Promise<PreuveTelephone>;

export interface CompteAuth {
  /** Création du compte Firebase Auth (posée par Google). */
  creeLe: Date | null;
  emailVerifie: boolean;
  email: string | undefined;
}

export interface ComptesAuth {
  lire(uid: string): Promise<CompteAuth>;
  /** Supprime la session « téléphone » devenue inutile, si c'est bien elle (jamais un vrai compte). */
  supprimerSessionTelephone(uid: string): Promise<boolean>;
}

/** Vérification réelle : signature, émetteur et expiration contrôlés par Firebase Admin. */
export const verifierJetonFirebase: VerifierJetonTelephone = async (jeton) => {
  const decode = await getAuth().verifyIdToken(jeton);
  const secondes = typeof decode.auth_time === 'number' ? decode.auth_time : undefined;
  return {
    uid: decode.uid,
    fournisseur: String(decode.firebase?.sign_in_provider ?? ''),
    telephone: typeof decode.phone_number === 'string' ? decode.phone_number : undefined,
    connecteLe: secondes === undefined ? undefined : new Date(secondes * 1000),
  };
};

export class ComptesFirebase implements ComptesAuth {
  async lire(uid: string): Promise<CompteAuth> {
    const compte = await getAuth().getUser(uid);
    const creation = compte.metadata.creationTime ? new Date(compte.metadata.creationTime) : null;
    return {
      creeLe: creation !== null && !Number.isNaN(creation.getTime()) ? creation : null,
      emailVerifie: compte.emailVerified,
      email: compte.email,
    };
  }

  async supprimerSessionTelephone(uid: string): Promise<boolean> {
    const compte = await getAuth().getUser(uid);
    // Seulement une session créée par le SMS : aucun e-mail, aucun autre fournisseur.
    if (compte.email || compte.providerData.length === 0 || compte.providerData.some((p) => p.providerId !== 'phone')) {
      return false;
    }
    await getAuth().deleteUser(uid);
    return true;
  }
}

const objet = (valeur: unknown): Record<string, unknown> =>
  typeof valeur === 'object' && valeur !== null && !Array.isArray(valeur) ? (valeur as Record<string, unknown>) : {};

// ---------------------------------------------------------------------
// 1. Validation du numéro (callable `validerTelephone`)
// ---------------------------------------------------------------------

/**
 * Pose la marque « numéro validé » sur le compte de l'appelant, sur preuve du
 * jeton de la session « téléphone ». Un numéro n'est validé que sur UN compte
 * par rôle (`telephones_valides/{rôle}_{numéro}`, lisible par ce serveur seul) :
 * comme l'annuaire de connexion, il reste permis à un compte Client et à un
 * compte Chauffeur de partager le même numéro. Rejouable : revalider le même
 * numéro ne change rien d'autre que la date.
 */
export async function validerTelephone(
  db: Firestore,
  verifier: VerifierJetonTelephone,
  comptes: Pick<ComptesAuth, 'supprimerSessionTelephone'>,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
  etat: EtatValidationTelephone = VALIDATION_TELEPHONE,
): Promise<{ valide: true; telephone: string }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous.');
  if (etat === 'fermee') {
    throw new HttpsError('failed-precondition', "La validation du numéro par SMS n'est pas encore ouverte.");
  }
  const jeton = objet(donnees).jeton;
  if (typeof jeton !== 'string' || jeton.length < 20 || jeton.length > LONGUEUR_MAX_JETON) {
    throw new HttpsError('invalid-argument', 'Demande invalide.');
  }

  let preuve: PreuveTelephone;
  try {
    preuve = await verifier(jeton);
  } catch (e) {
    logger.info('Validation du téléphone : jeton refusé', { uid, erreur: String((e as Error)?.message ?? e).slice(0, 120) });
    throw new HttpsError('permission-denied', MESSAGE_CODE_INVALIDE);
  }
  if (preuve.fournisseur !== 'phone' || preuve.uid === uid) {
    throw new HttpsError('permission-denied', MESSAGE_CODE_INVALIDE);
  }
  const ecart = preuve.connecteLe === undefined ? Number.NaN : maintenant.getTime() - preuve.connecteLe.getTime();
  if (!(ecart >= -TOLERANCE_HORLOGE_MS) || ecart > FRAICHEUR_CODE_MS) {
    throw new HttpsError('permission-denied', 'Ce code a expiré. Demandez-en un nouveau.');
  }
  const telephone = telephoneE164(preuve.telephone);
  if (telephone === null) {
    throw new HttpsError('permission-denied', 'Seuls les numéros mobiles du Sénégal (+221) peuvent être validés.');
  }

  const refProfil = db.doc(`users/${uid}`);
  await db.runTransaction(async (tx) => {
    const profil = await tx.get(refProfil);
    const role = profil.get('role');
    if (!profil.exists || !(ROLES as readonly string[]).includes(role)) {
      throw new HttpsError('permission-denied', 'Seuls les comptes Client et Chauffeur valident un numéro.');
    }
    if (telephoneE164(profil.get('telephone')) !== telephone) {
      throw new HttpsError(
        'failed-precondition',
        "Ce numéro n'est pas celui de votre compte. Corrigez-le sur cette page, puis demandez un nouveau code.",
      );
    }
    const refCle = db.doc(`telephones_valides/${role}_${telephone}`);
    const cle = await tx.get(refCle);
    if (cle.exists && cle.get('uid') !== uid) {
      throw new HttpsError(
        'already-exists',
        'Ce numéro est déjà validé sur un autre compte Sprint. Utilisez un autre numéro ou contactez le support.',
      );
    }
    // Un seul numéro validé par compte : l'ancien est libéré.
    const anciennes = await tx.get(db.collection('telephones_valides').where('uid', '==', uid));
    for (const ancienne of anciennes.docs) if (ancienne.id !== refCle.id) tx.delete(ancienne.ref);
    tx.set(refCle, { uid, role, telephone, valideLe: Timestamp.fromDate(maintenant) });
    tx.update(refProfil, {
      telephoneVerifie: true,
      telephoneValide: telephone,
      telephoneVerifieLe: Timestamp.fromDate(maintenant),
    });
  });

  // Nettoyage sans conséquence : la session « téléphone » ne sert plus.
  try {
    await comptes.supprimerSessionTelephone(preuve.uid);
  } catch (e) {
    logger.warn('Validation du téléphone : session « téléphone » non supprimée', { erreur: String((e as Error)?.message ?? e).slice(0, 120) });
  }
  return { valide: true, telephone };
}

// ---------------------------------------------------------------------
// 2. Message de bienvenue (callable `declencherBienvenue`)
// ---------------------------------------------------------------------

export interface MessageBienvenue {
  titre: string;
  /** Notification : une ligne. */
  notification: string;
  /** Accroche de l'écran et de l'e-mail. */
  accroche: string;
  /** Ce que la personne peut faire maintenant. */
  points: string[];
}

/** Premier prénom propre à afficher : le prénom du profil, sinon le premier mot du nom. */
export function prenomPour(profil: { get(champ: string): unknown }): string {
  const brut = [profil.get('prenom'), profil.get('nom')].find((v) => typeof v === 'string' && v.trim() !== '');
  const mot = typeof brut === 'string' ? (brut.trim().split(/\s+/)[0] ?? '') : '';
  return mot.replace(/[<>&"'`\u0000-\u001F]/g, '').slice(0, 40);
}

/** Le texte de « Bienvenue chez SPRINT », selon le rôle (mêmes mots dans l'app). */
export function messageBienvenue(role: string, prenom: string): MessageBienvenue {
  const bonjour = prenom ? `Bonjour ${prenom},` : 'Bonjour,';
  if (role === 'conducteur') {
    return {
      titre: 'Bienvenue chez SPRINT',
      notification: 'Complétez votre dossier pour commencer à recevoir des courses.',
      accroche: `${bonjour} bienvenue dans l'équipe SPRINT.`,
      points: [
        'Complétez votre dossier (pièces et moto) : un administrateur le valide avant votre première course.',
        'Une fois validé, passez « En ligne » pour recevoir les courses autour de vous.',
        "Vos gains s'affichent course après course dans l'onglet Gains.",
      ],
    };
  }
  return {
    titre: 'Bienvenue chez SPRINT',
    notification: 'Votre compte est prêt : commandez votre première course quand vous voulez.',
    accroche: `${bonjour} votre compte SPRINT est prêt.`,
    points: [
      'Commandez une course en moto en quelques secondes : le prix est affiché avant de confirmer.',
      'Envoyez un colis partout à Dakar, Thiès et Mbour.',
      'Suivez votre chauffeur en direct sur la carte.',
    ],
  };
}

const echapperHtml = (texte: string) =>
  texte.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

/** Adresse que les réponses des e-mails de Sprint atteignent (déjà publiée dans l'app). */
export const ADRESSE_SUPPORT = 'support@groupesantine.sn';

/**
 * Document pour l'extension « Trigger Email from Firestore » (collection
 * `mail`) : destinataire, objet, texte simple et HTML. L'adresse d'expédition
 * est celle réglée dans l'extension (domaine officiel).
 */
export function courrielBienvenue(email: string, message: MessageBienvenue) {
  const items = message.points.map((p) => `<li style="margin:0 0 8px">${echapperHtml(p)}</li>`).join('');
  const html =
    '<div style="background:#0B0B0C;padding:24px 12px;font-family:Arial,Helvetica,sans-serif">' +
    '<div style="max-width:520px;margin:0 auto;background:#141416;border-radius:16px;padding:28px;color:#F5F5F7">' +
    '<div style="font-size:13px;letter-spacing:3px;font-weight:700;color:#22E07A">SPRINT</div>' +
    `<h1 style="margin:12px 0 8px;font-size:24px;line-height:1.25;color:#F5F5F7">${echapperHtml(message.titre)}</h1>` +
    `<p style="margin:0 0 16px;font-size:15px;line-height:1.5;color:#F5F5F7">${echapperHtml(message.accroche)}</p>` +
    `<ul style="margin:0 0 20px;padding-left:20px;font-size:14px;line-height:1.5;color:#C9C9CF">${items}</ul>` +
    `<p style="margin:0;font-size:12px;line-height:1.5;color:#9A9AA2">Une question ? Répondez à ce message ou écrivez à ${ADRESSE_SUPPORT}.</p>` +
    '</div></div>';
  const texte = [message.titre, '', message.accroche, '', ...message.points.map((p) => `- ${p}`), '', `Une question ? Écrivez à ${ADRESSE_SUPPORT}.`].join('\n');
  return {
    to: [email],
    replyTo: ADRESSE_SUPPORT,
    message: { subject: message.titre, text: texte, html },
  };
}

export interface ResultatBienvenue {
  envoye: boolean;
  raison?: string;
  /** Pour l'écran de bienvenue de l'app. */
  role?: string;
}

/**
 * Envoie « Bienvenue chez SPRINT » UNE SEULE FOIS à un nouveau compte dont
 * l'inscription est complète : e-mail vérifié (relu chez Firebase Auth, pas
 * dans le jeton de l'appelant, qui peut dater d'avant la vérification) et,
 * quand la validation du téléphone est obligatoire, numéro validé. Les
 * comptes créés avant l'ouverture ne reçoivent rien. Refus et raisons ne
 * sont pas des erreurs : l'app n'affiche rien si `envoye` est faux.
 */
export async function declencherBienvenue(
  db: Firestore,
  comptes: Pick<ComptesAuth, 'lire'>,
  messagerie: Messagerie | undefined,
  uid: string | undefined,
  maintenant: Date,
  reglages: {
    bienvenue?: boolean;
    email?: boolean;
    validation?: EtatValidationTelephone;
    nouveauxComptesDepuis?: Date;
  } = {},
): Promise<ResultatBienvenue> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous.');
  const { bienvenue = BIENVENUE_AUTOMATIQUE, email = EMAIL_BIENVENUE, validation = VALIDATION_TELEPHONE } = reglages;
  const depuis = reglages.nouveauxComptesDepuis ?? NOUVEAUX_COMPTES_DEPUIS;
  if (!bienvenue) return { envoye: false, raison: 'ferme' };

  const compte = await comptes.lire(uid);
  if (compte.creeLe === null || compte.creeLe.getTime() < depuis.getTime()) return { envoye: false, raison: 'compte_ancien' };
  if (!compte.emailVerifie) return { envoye: false, raison: 'email_non_verifie' };

  const refProfil = db.doc(`users/${uid}`);
  const resultat = await db.runTransaction(async (tx): Promise<ResultatBienvenue & { prenom?: string }> => {
    const profil = await tx.get(refProfil);
    const role = profil.get('role');
    if (!profil.exists || !(ROLES as readonly string[]).includes(role)) return { envoye: false, raison: 'role' };
    if (profil.get('bienvenueEnvoyeeLe')) return { envoye: false, raison: 'deja_envoye' };
    if (validation === 'obligatoire') {
      const valide = profil.get('telephoneVerifie') === true && telephoneE164(profil.get('telephone')) === profil.get('telephoneValide');
      if (!valide) return { envoye: false, raison: 'telephone_non_valide' };
    }
    const prenom = prenomPour(profil);
    tx.update(refProfil, { bienvenueEnvoyeeLe: Timestamp.fromDate(maintenant) });
    if (email && compte.email) {
      tx.set(db.doc(`mail/bienvenue_${uid}`), courrielBienvenue(compte.email, messageBienvenue(role, prenom)));
    }
    return { envoye: true, role, prenom };
  });
  if (!resultat.envoye) return { envoye: false, raison: resultat.raison };

  // Notification sur les appareils du compte, s'il y en a déjà : sans conséquence si aucune.
  const message = messageBienvenue(resultat.role ?? 'client', resultat.prenom ?? '');
  await pousser(db, messagerie, [uid], {
    titre: message.titre,
    corps: message.notification,
    canal: 'messages',
    lien: resultat.role === 'conducteur' ? LIENS.chauffeur : LIENS.accueilClient,
    donnees: { type: 'bienvenue' },
    dureeVieSecondes: 24 * 3600,
  });
  return { envoye: true, role: resultat.role };
}
