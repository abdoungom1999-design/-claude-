import { Timestamp, type Firestore } from 'firebase-admin/firestore';
import { getMessaging, type MulticastMessage } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Notifications push (Android) : elles arrivent même quand l'app est fermée.
 *
 * Les téléphones enregistrent leur jeton FCM dans
 * `appareils/{uid}/jetons/{jeton}` (voir firestore.rules). Le serveur seul
 * envoie, et seulement dans ces cas :
 *   - message du chauffeur au client (ou l'inverse) pendant leur course ;
 *   - nouvelle course, aux chauffeurs en ligne, libres et non sanctionnés ;
 *   - course acceptée, au client ;
 *   - course annulée par le chauffeur ou faute de chauffeur, au client.
 *
 * Trois sortes de téléphones reçoivent la même notification : l'APK
 * Android, le site ouvert dans un navigateur (Chrome, Edge, Firefox,
 * Safari) et le site installé sur l'écran d'accueil d'un iPhone (iOS 16.4
 * minimum). Le jeton de chacun dit où l'envoyer ; l'envoi ajoute la partie
 * "web push" (icône, lien à ouvrir au clic) à la partie Android.
 *
 * Une notification qui échoue ne doit JAMAIS faire échouer ce qui l'a
 * déclenchée (paiement, annulation...) : [pousser] ne lève pas d'erreur.
 * Le texte d'un message figure dans la notification (choix du client :
 * lisible sans déverrouiller) ; il n'est jamais fourni par l'appelant, le
 * serveur le relit dans le message enregistré.
 */

export type Canal = 'messages' | 'courses';

export interface EnvoiPush {
  titre: string;
  corps: string;
  /** Canal de notification Android (créé par l'app : son et importance). */
  canal: Canal;
  /** Lu par l'app à l'appui sur la notification. Valeurs : chaînes. */
  donnees: Record<string, string>;
  /**
   * Où mène l'appui sur la notification quand elle vient du site : chemin
   * dans l'app, adresses en `#` (ex. `/#/accueil/messages`).
   */
  lien: string;
  /** Passé ce délai, la notification n'a plus d'intérêt (course prise par un autre...). */
  dureeVieSecondes: number;
}

export interface Messagerie {
  /** Envoie à ces jetons ; renvoie ceux que Google déclare morts (à supprimer). */
  envoyer(jetons: string[], push: EnvoiPush): Promise<{ envoyes: number; invalides: string[] }>;
}

/** Adresse publique du site (Firebase Hosting) : les liens des notifications web sont absolus. */
export const SITE = 'https://sprint-vtc.web.app';

/** Destinations dans l'app (adresses en `#`, comme le routeur du site). */
export const LIENS = {
  messagesClient: '/#/accueil/messages',
  activiteClient: '/#/accueil/activite',
  chauffeur: '/#/conducteur',
} as const;

const CODES_JETON_MORT = [
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
];

/** Message FCM pour ces jetons : partie Android et partie site (web push, iPhone). */
export function messageFcm(jetons: string[], push: EnvoiPush): MulticastMessage {
  return {
    tokens: jetons,
    notification: { title: push.titre, body: push.corps },
    data: push.donnees,
    android: {
      // Priorité haute : réveille le téléphone même en veille.
      priority: 'high',
      ttl: push.dureeVieSecondes * 1000,
      notification: { channelId: push.canal, sound: 'default' },
    },
    // Site (navigateur, iPhone) : le texte est celui de `notification`,
    // affiché par le service worker même site fermé.
    webpush: {
      headers: { TTL: String(push.dureeVieSecondes), Urgency: 'high' },
      notification: { icon: `${SITE}/icons/Icon-192.png`, badge: `${SITE}/icons/Icon-192.png` },
      fcmOptions: { link: `${SITE}${push.lien}` },
    },
  };
}

/** Envoi réel par Firebase Cloud Messaging. */
export class MessagerieFcm implements Messagerie {
  async envoyer(jetons: string[], push: EnvoiPush) {
    let envoyes = 0;
    const invalides: string[] = [];
    // 500 jetons au plus par envoi groupé.
    for (let i = 0; i < jetons.length; i += 500) {
      const lot = jetons.slice(i, i + 500);
      const reponse = await getMessaging().sendEachForMulticast(messageFcm(lot, push));
      reponse.responses.forEach((r, index) => {
        if (r.success) envoyes++;
        else if (r.error && CODES_JETON_MORT.includes(r.error.code)) invalides.push(lot[index]);
      });
    }
    return { envoyes, invalides };
  }
}

/** Jetons des appareils de ces utilisateurs. */
async function jetonsDe(db: Firestore, uids: string[]): Promise<{ uid: string; jeton: string }[]> {
  const resultat: { uid: string; jeton: string }[] = [];
  for (const uid of uids) {
    const docs = await db.collection(`appareils/${uid}/jetons`).get();
    for (const doc of docs.docs) resultat.push({ uid, jeton: doc.id });
  }
  return resultat;
}

/**
 * Envoie [push] aux appareils de [uids] et supprime les jetons morts.
 * Ne lève jamais d'erreur (voir l'en-tête du fichier).
 */
export async function pousser(
  db: Firestore,
  messagerie: Messagerie | undefined,
  uids: string[],
  push: EnvoiPush,
): Promise<number> {
  if (!messagerie || uids.length === 0) return 0;
  try {
    const appareils = await jetonsDe(db, uids);
    if (appareils.length === 0) return 0;
    const { envoyes, invalides } = await messagerie.envoyer(
      appareils.map((a) => a.jeton),
      push,
    );
    await Promise.all(
      appareils
        .filter((a) => invalides.includes(a.jeton))
        .map((a) => db.doc(`appareils/${a.uid}/jetons/${a.jeton}`).delete()),
    );
    return envoyes;
  } catch (e) {
    logger.warn('Notification push non envoyée', { erreur: String(e) });
    return 0;
  }
}

// ---------------------------------------------------------------------
// Aides
// ---------------------------------------------------------------------

const STATUTS_ACTIFS = ['acceptee', 'en_cours'];
const IDENTIFIANT = /^[A-Za-z0-9]{1,128}$/;

/** Longueur maximale du texte d'un message dans la notification. */
export const LONGUEUR_MAX_TEXTE = 240;

/** Un message n'est notifié que s'il vient d'être écrit. */
export const FRAICHEUR_MESSAGE_MS = 5 * 60 * 1000;

function texteCourt(texte: string, max: number): string {
  const propre = texte.replace(/\s+/g, ' ').trim();
  return propre.length <= max ? propre : `${propre.slice(0, max - 1)}…`;
}

function donneesRequete(donnees: unknown): Record<string, unknown> {
  return typeof donnees === 'object' && donnees !== null ? (donnees as Record<string, unknown>) : {};
}

function identifiant(valeur: unknown, nom: string): string {
  if (typeof valeur !== 'string' || !IDENTIFIANT.test(valeur)) {
    throw new HttpsError('invalid-argument', `${nom} invalide.`);
  }
  return valeur;
}

/** Nom public (profils_publics) ; à défaut, [parDefaut]. */
async function nomPublic(db: Firestore, uid: string, parDefaut: string): Promise<string> {
  const profil = await db.doc(`profils_publics/${uid}`).get();
  const nom = profil.get('nom');
  return typeof nom === 'string' && nom.trim() ? nom.trim() : parDefaut;
}

// ---------------------------------------------------------------------
// 1. Message (callable `notifierMessage`, appelée par l'expéditeur)
// ---------------------------------------------------------------------

/**
 * Prévient l'autre partie qu'un message vient d'arriver. L'appelant ne
 * fournit que l'identifiant du message et le destinataire : le texte est
 * relu ici, dans le message réellement enregistré, et chaque message ne
 * produit qu'une seule notification (`notifieLe`). Refusé sans course en
 * cours entre les deux : on ne fait pas sonner le téléphone de n'importe
 * qui.
 */
export async function notifierMessage(
  db: Firestore,
  messagerie: Messagerie,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
): Promise<{ envoye: boolean; raison?: string }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous.');
  const d = donneesRequete(donnees);
  const messageId = identifiant(d.messageId, 'Message');
  const destinataireId = identifiant(d.destinataireId, 'Destinataire');
  if (destinataireId === uid) throw new HttpsError('invalid-argument', 'Destinataire invalide.');

  const chatId = [uid, destinataireId].sort().join('_');
  const refMessage = db.doc(`chats/${chatId}/messages/${messageId}`);
  const message = await refMessage.get();
  if (!message.exists) throw new HttpsError('not-found', 'Message introuvable.');
  if (message.get('senderId') !== uid) throw new HttpsError('permission-denied', 'Ce message n’est pas le vôtre.');
  const ecritLe = message.get('timestamp');
  if (!(ecritLe instanceof Timestamp) || maintenant.getTime() - ecritLe.toMillis() > FRAICHEUR_MESSAGE_MS) {
    return { envoye: false, raison: 'trop_ancien' };
  }

  // Course en cours entre les deux, dans un sens ou dans l'autre.
  let course: { id: string; chauffeurId: string } | undefined;
  for (const [clientId, chauffeurId] of [
    [uid, destinataireId],
    [destinataireId, uid],
  ]) {
    const trouvees = await db
      .collection('courses')
      .where('clientId', '==', clientId)
      .where('chauffeurId', '==', chauffeurId)
      .get();
    const active = trouvees.docs.find((c) => STATUTS_ACTIFS.includes(c.get('statut')));
    if (active) {
      course = { id: active.id, chauffeurId };
      break;
    }
  }
  if (!course) throw new HttpsError('permission-denied', 'Aucune course en cours avec ce destinataire.');

  const premiere = await db.runTransaction(async (tx) => {
    const actuel = await tx.get(refMessage);
    if (actuel.get('notifieLe')) return false;
    tx.update(refMessage, { notifieLe: Timestamp.fromDate(maintenant) });
    return true;
  });
  if (!premiere) return { envoye: false, raison: 'deja_notifie' };

  const expediteurEstChauffeur = course.chauffeurId === uid;
  const nom = await nomPublic(db, uid, expediteurEstChauffeur ? 'Votre chauffeur' : 'Votre client');
  const texte = texteCourt(String(message.get('text') ?? ''), LONGUEUR_MAX_TEXTE);
  const envoyes = await pousser(db, messagerie, [destinataireId], {
    titre: nom,
    corps: texte || 'Nouveau message',
    canal: 'messages',
    lien: expediteurEstChauffeur ? LIENS.messagesClient : LIENS.chauffeur,
    donnees: { type: 'message', expediteurId: uid, courseId: course.id },
    dureeVieSecondes: 60 * 60,
  });
  return { envoye: envoyes > 0 };
}

// ---------------------------------------------------------------------
// 2. Course acceptée (callable `notifierAcceptation`, par le chauffeur)
// ---------------------------------------------------------------------

/** Prévient le client que son chauffeur arrive (une seule fois par course). */
export async function notifierAcceptation(
  db: Firestore,
  messagerie: Messagerie,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
): Promise<{ envoye: boolean; raison?: string }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous.');
  const courseId = identifiant(donneesRequete(donnees).courseId, 'Course');
  const ref = db.doc(`courses/${courseId}`);

  const resultat = await db.runTransaction(async (tx) => {
    const course = await tx.get(ref);
    if (!course.exists) throw new HttpsError('not-found', 'Course introuvable.');
    if (course.get('chauffeurId') !== uid) throw new HttpsError('permission-denied', 'Cette course n’est pas la vôtre.');
    if (!STATUTS_ACTIFS.includes(course.get('statut'))) {
      throw new HttpsError('failed-precondition', 'Cette course n’est plus en cours.');
    }
    if (course.get('notifAccepteeLe')) return null;
    tx.update(ref, { notifAccepteeLe: Timestamp.fromDate(maintenant) });
    return { clientId: course.get('clientId') as string };
  });
  if (!resultat) return { envoye: false, raison: 'deja_notifie' };

  const profil = await db.doc(`profils_publics/${uid}`).get();
  const nom = await nomPublic(db, uid, 'Votre chauffeur');
  const vehicule = [profil.get('vehiculeId'), profil.get('plaqueImmatriculation')]
    .filter((v): v is string => typeof v === 'string' && v.trim() !== '')
    .join(' · ');
  const envoyes = await pousser(db, messagerie, [resultat.clientId], {
    titre: 'Chauffeur trouvé !',
    corps: vehicule ? `${nom} arrive · ${vehicule}` : `${nom} arrive pour vous prendre.`,
    canal: 'courses',
    lien: LIENS.activiteClient,
    donnees: { type: 'acceptee', courseId },
    dureeVieSecondes: 10 * 60,
  });
  return { envoye: envoyes > 0 };
}

// ---------------------------------------------------------------------
// 3. Nouvelle course (appelée par le webhook de paiement)
// ---------------------------------------------------------------------

/** Nombre maximal de chauffeurs prévenus pour une même course. */
export const MAX_CHAUFFEURS_PREVENUS = 100;

/** Chauffeurs validés, non sanctionnés, en ligne et sans course en cours. */
export async function chauffeursEligibles(db: Firestore): Promise<string[]> {
  const enLigne = await db
    .collection('users')
    .where('role', '==', 'conducteur')
    .where('statut', '==', 'EN_LIGNE')
    .get();
  const occupes = new Set<string>();
  const actives = await db.collection('courses').where('statut', 'in', STATUTS_ACTIFS).get();
  for (const c of actives.docs) {
    const chauffeurId = c.get('chauffeurId');
    if (typeof chauffeurId === 'string') occupes.add(chauffeurId);
  }
  return enLigne.docs
    .filter((u) => u.get('statutValidation') === 'valide')
    .filter((u) => !['suspendu', 'banni'].includes(u.get('statutCompte') ?? 'actif'))
    .filter((u) => !occupes.has(u.id))
    .map((u) => u.id)
    .slice(0, MAX_CHAUFFEURS_PREVENUS);
}

const fcfa = (montant: number) => `${Math.round(montant).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ')} FCFA`;

/** Prévient les chauffeurs disponibles qu'une course vient d'être demandée. */
export async function notifierNouvelleCourse(
  db: Firestore,
  messagerie: Messagerie | undefined,
  courseId: string,
): Promise<number> {
  if (!messagerie) return 0;
  try {
    const course = await db.doc(`courses/${courseId}`).get();
    if (!course.exists || course.get('statut') !== 'en_attente') return 0;
    const chauffeurs = await chauffeursEligibles(db);
    const prix = course.get('prixFcfa');
    return await pousser(db, messagerie, chauffeurs, {
      titre: course.get('type') === 'COLIS' ? 'Nouveau colis à livrer' : 'Nouvelle course',
      corps: `${course.get('adresseDepart')} → ${course.get('adresseArrivee')}${typeof prix === 'number' ? ` · ${fcfa(prix)}` : ''}`,
      canal: 'courses',
      lien: LIENS.chauffeur,
      donnees: { type: 'course', courseId },
      // Une demande non prise au bout de 2 minutes n'a plus à réveiller personne.
      dureeVieSecondes: 2 * 60,
    });
  } catch (e) {
    logger.warn('Nouvelle course : notification impossible', { courseId, erreur: String(e) });
    return 0;
  }
}

// ---------------------------------------------------------------------
// 4. Annulation (appelée par annulerCourse et la surveillance)
// ---------------------------------------------------------------------

/** Prévient le client que sa course a été annulée par son chauffeur ou faute de chauffeur. */
export async function notifierAnnulation(
  db: Firestore,
  messagerie: Messagerie | undefined,
  clientId: unknown,
  courseId: string,
  par: 'chauffeur' | 'systeme',
): Promise<number> {
  if (typeof clientId !== 'string') return 0;
  return pousser(db, messagerie, [clientId], {
    titre: par === 'chauffeur' ? 'Course annulée par votre chauffeur' : 'Aucun chauffeur disponible',
    corps:
      par === 'chauffeur'
        ? 'Votre paiement sera remboursé. Vous pouvez commander de nouveau.'
        : 'Votre course est annulée et votre paiement sera remboursé.',
    canal: 'courses',
    lien: LIENS.activiteClient,
    donnees: { type: 'annulee', courseId },
    dureeVieSecondes: 60 * 60,
  });
}
