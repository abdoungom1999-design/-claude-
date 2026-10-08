import { createHash } from 'node:crypto';
import { Timestamp, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Connexion par numéro de téléphone, sans annuaire public.
 *
 * Avant : l'app lisait `annuaire_telephones/{rôle}_{téléphone}` (lecture
 * ouverte à tous, nécessaire avant d'être connecté) pour retrouver l'e-mail
 * du compte. N'importe qui pouvait donc tester des numéros pour savoir qui
 * a un compte Sprint et récupérer son e-mail.
 *
 * Maintenant : l'annuaire n'est lisible que par ce serveur. `connexionTelephone`
 * vérifie d'abord le mot de passe auprès de Firebase Auth, et ne rend l'e-mail
 * qu'à celui qui le connaît (le propriétaire du compte : il ne découvre rien
 * qu'il ne sache déjà). Numéro inconnu et mot de passe faux donnent la même
 * réponse, au même rythme, et les essais sont limités par numéro et par
 * adresse réseau. L'app termine ensuite la connexion normalement
 * (e-mail + mot de passe), avec une vraie session Firebase.
 *
 * `synchroniserAnnuaire` écrit l'entrée de l'appelant (et seulement la
 * sienne) d'après son profil `users/{uid}`, puisque l'app n'a plus le droit
 * d'écrire dans l'annuaire.
 */

export const ROLES_CONNEXION = ['client', 'conducteur'] as const;
export const MESSAGE_IDENTIFIANTS = 'Numéro ou mot de passe incorrect.';
const MESSAGE_TROP_D_ESSAIS = 'Trop de tentatives. Réessayez dans quelques minutes.';
const MESSAGE_INDISPONIBLE = "La connexion par téléphone est momentanément indisponible. Utilisez votre e-mail.";

const LONGUEUR_MAX_TELEPHONE = 40;
const LONGUEUR_MAX_MOT_DE_PASSE = 4096;

/** Un refus prend au moins ce temps : « numéro inconnu » ne se devine pas à la vitesse de la réponse. */
export const DUREE_MIN_ECHEC_MS = 800;

export interface PolitiqueLimite {
  /** Échecs tolérés dans la fenêtre. */
  seuil: number;
  fenetreMs: number;
  blocageMs: number;
}

/** Par numéro (qu'il existe ou non) : 5 échecs en 15 minutes bloquent 15 minutes. */
export const LIMITE_TELEPHONE: PolitiqueLimite = { seuil: 5, fenetreMs: 15 * 60_000, blocageMs: 15 * 60_000 };
/** Par adresse réseau : large, car plusieurs abonnés mobiles peuvent partager une même adresse. */
export const LIMITE_ADRESSE: PolitiqueLimite = { seuil: 100, fenetreMs: 15 * 60_000, blocageMs: 15 * 60_000 };

export type ResultatMotDePasse = 'ok' | 'refuse' | 'limite' | 'indisponible';
/** Vérifie un mot de passe auprès de Firebase Auth (sans ouvrir de session pour l'appelant). */
export type VerifierMotDePasse = (email: string, motDePasse: string) => Promise<ResultatMotDePasse>;

export interface ContexteAppel {
  /** Adresse réseau de l'appelant (celle que Google a vue), si connue. */
  adresse?: string;
}

/** Identifiant de l'entrée d'annuaire (même forme que l'app), `null` si le numéro ne peut pas servir d'identifiant. */
export function cleAnnuaire(role: string, telephone: string): string | null {
  const numero = telephone.trim();
  if (numero.length === 0 || numero.length > LONGUEUR_MAX_TELEPHONE || numero.includes('/')) return null;
  return `${role}_${numero}`;
}

const empreinte = (texte: string) => createHash('sha256').update(texte).digest('hex').slice(0, 40);

/** Identifiants des compteurs d'essais : ni numéro ni adresse en clair. */
export const cleLimiteNumero = (role: string, telephone: string) => `tel_${empreinte(`${role}_${telephone.trim()}`)}`;
export const cleLimiteAdresse = (adresse: string) => `ip_${empreinte(adresse)}`;
const attendre = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

function objet(valeur: unknown): Record<string, unknown> {
  return typeof valeur === 'object' && valeur !== null && !Array.isArray(valeur) ? (valeur as Record<string, unknown>) : {};
}

// --- Limitation des essais ---------------------------------------------------

async function estBloque(db: Firestore, cle: string, maintenant: Date): Promise<boolean> {
  const jusqua = (await db.collection('limites_connexion').doc(cle).get()).get('bloqueJusqua');
  return jusqua instanceof Timestamp && jusqua.toMillis() > maintenant.getTime();
}

async function noterEchec(db: Firestore, cle: string, politique: PolitiqueLimite, maintenant: Date): Promise<void> {
  const ref = db.collection('limites_connexion').doc(cle);
  await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const debut = doc.get('debutLe');
    const dansLaFenetre = debut instanceof Timestamp && maintenant.getTime() - debut.toMillis() < politique.fenetreMs;
    const echecs = (dansLaFenetre ? Number(doc.get('echecs') ?? 0) : 0) + 1;
    tx.set(ref, {
      echecs,
      debutLe: dansLaFenetre ? debut : Timestamp.fromDate(maintenant),
      // Pour une règle de durée de vie (TTL) Firestore : les compteurs ne s'accumulent pas.
      expireLe: Timestamp.fromMillis(maintenant.getTime() + 24 * 3_600_000),
      ...(echecs >= politique.seuil ? { bloqueJusqua: Timestamp.fromMillis(maintenant.getTime() + politique.blocageMs) } : {}),
    });
  });
}

// --- Connexion par téléphone ---------------------------------------------------

/**
 * Callable `connexionTelephone` (appelable sans être connecté). Rend l'e-mail
 * du compte si, et seulement si, le mot de passe est le bon.
 */
export async function connexionTelephone(
  db: Firestore,
  verifier: VerifierMotDePasse,
  contexte: ContexteAppel,
  donnees: unknown,
  maintenant: Date,
  dormir: (ms: number) => Promise<void> = attendre,
  horloge: () => number = Date.now,
): Promise<{ email: string }> {
  const debut = horloge();
  const d = objet(donnees);
  const { role, telephone, motDePasse } = d;
  if (
    typeof role !== 'string' ||
    !(ROLES_CONNEXION as readonly string[]).includes(role) ||
    typeof telephone !== 'string' ||
    telephone.length > 4 * LONGUEUR_MAX_TELEPHONE ||
    typeof motDePasse !== 'string' ||
    motDePasse.length === 0 ||
    motDePasse.length > LONGUEUR_MAX_MOT_DE_PASSE
  ) {
    throw new HttpsError('invalid-argument', 'Demande de connexion invalide.');
  }

  const refuser = async (code: 'permission-denied' | 'resource-exhausted', message: string): Promise<never> => {
    const reste = DUREE_MIN_ECHEC_MS - (horloge() - debut);
    if (reste > 0) await dormir(reste);
    throw new HttpsError(code, message);
  };

  const cle = cleAnnuaire(role, telephone);
  // Un numéro inutilisable ou inconnu est compté comme n'importe quel autre.
  const cleNumero = cleLimiteNumero(role, telephone);
  const cleAdresse = contexte.adresse ? cleLimiteAdresse(contexte.adresse) : null;

  if ((await estBloque(db, cleNumero, maintenant)) || (cleAdresse !== null && (await estBloque(db, cleAdresse, maintenant)))) {
    return refuser('resource-exhausted', MESSAGE_TROP_D_ESSAIS);
  }

  const echouer = async (): Promise<never> => {
    await Promise.all([
      noterEchec(db, cleNumero, LIMITE_TELEPHONE, maintenant),
      cleAdresse !== null ? noterEchec(db, cleAdresse, LIMITE_ADRESSE, maintenant) : Promise.resolve(),
    ]);
    return refuser('permission-denied', MESSAGE_IDENTIFIANTS);
  };

  if (cle === null) return echouer();
  const email = (await db.collection('annuaire_telephones').doc(cle).get()).get('email');
  if (typeof email !== 'string') return echouer();

  switch (await verifier(email, motDePasse)) {
    case 'ok':
      await db.collection('limites_connexion').doc(cleNumero).delete();
      return { email };
    case 'refuse':
      return echouer();
    case 'limite':
      // Firebase Auth freine déjà ce compte : même message que notre propre limite.
      return refuser('resource-exhausted', MESSAGE_TROP_D_ESSAIS);
    default:
      throw new HttpsError('unavailable', MESSAGE_INDISPONIBLE);
  }
}

/** Vraie vérification : API REST de Firebase Auth (le mot de passe n'est jamais journalisé). */
export function verifierMotDePasseFirebase(
  cleApi: string,
  fetcher: typeof fetch = fetch,
  hote = hoteIdentite(),
): VerifierMotDePasse {
  return async (email, motDePasse) => {
    let reponse: Response;
    try {
      reponse = await fetcher(`${hote}/v1/accounts:signInWithPassword?key=${encodeURIComponent(cleApi)}`, {
        method: 'POST',
        // La clé web peut être restreinte au site : on se présente comme lui.
        headers: { 'Content-Type': 'application/json', Referer: 'https://sprint-vtc.web.app/' },
        body: JSON.stringify({ email, password: motDePasse, returnSecureToken: true }),
        signal: AbortSignal.timeout(10_000),
      });
    } catch (e) {
      logger.error('Vérification du mot de passe : Firebase Auth injoignable', { erreur: String((e as Error).message) });
      return 'indisponible';
    }
    if (reponse.ok) return 'ok';
    const code = String(((await reponse.json().catch(() => ({}))) as { error?: { message?: unknown } }).error?.message ?? '');
    if (/^(INVALID_PASSWORD|EMAIL_NOT_FOUND|INVALID_LOGIN_CREDENTIALS|INVALID_EMAIL|MISSING_PASSWORD|USER_DISABLED)/.test(code)) {
      return 'refuse';
    }
    if (/^TOO_MANY_ATTEMPTS_TRY_LATER/.test(code)) return 'limite';
    logger.error('Vérification du mot de passe : réponse inattendue de Firebase Auth', { statut: reponse.status, code });
    return 'indisponible';
  };
}

/** Émulateur Auth en test (FIREBASE_AUTH_EMULATOR_HOST), Google sinon. */
export function hoteIdentite(env: NodeJS.ProcessEnv = process.env): string {
  return env.FIREBASE_AUTH_EMULATOR_HOST
    ? `http://${env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com`
    : 'https://identitytoolkit.googleapis.com';
}

// --- Annuaire côté serveur ---------------------------------------------------

/**
 * Callable `synchroniserAnnuaire` : publie l'entrée d'annuaire de l'appelant
 * d'après son profil, et retire ses anciennes entrées (numéro changé). Un
 * numéro déjà pris par un autre compte n'est jamais écrasé.
 */
export async function synchroniserAnnuaire(
  db: Firestore,
  uid: string | undefined,
  email: string | undefined,
): Promise<{ publie: boolean }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous.');
  if (!email) throw new HttpsError('failed-precondition', 'Ce compte n\'a pas d\'adresse e-mail.');

  const profil = await db.collection('users').doc(uid).get();
  const role = profil.get('role');
  const telephone = profil.get('telephone');
  const cle =
    (role === 'client' || role === 'conducteur') && typeof telephone === 'string' ? cleAnnuaire(role, telephone) : null;

  let publie = false;
  if (cle !== null) {
    const ref = db.collection('annuaire_telephones').doc(cle);
    publie = await db.runTransaction(async (tx) => {
      const actuelle = await tx.get(ref);
      if (actuelle.exists && actuelle.get('uid') !== uid) return false;
      tx.set(ref, { uid, email });
      return true;
    });
  }

  // Seule l'entrée du numéro actuel peut rester : l'ancien numéro ne permet plus de se connecter.
  const siennes = await db.collection('annuaire_telephones').where('uid', '==', uid).get();
  await Promise.all(siennes.docs.filter((d) => !publie || d.id !== cle).map((d) => d.ref.delete()));
  return { publie };
}
