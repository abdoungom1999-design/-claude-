import { getAuth } from 'firebase-admin/auth';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { ErreurResend, type CourrielResend, type EnvoiCourriel } from './email_resend';
import { ADRESSE_CONTACT } from './inscription';

/**
 * E-mail « Bienvenue chez SPRINT : votre compte chauffeur est activé », envoyé
 * UNE SEULE FOIS, au moment où l'Admin approuve le dossier d'un chauffeur
 * (`users/{uid}.statutValidation` passe à `valide`). L'envoi se fait
 * directement par l'API Resend (voir `email_resend.ts`) depuis une Cloud
 * Function déclenchée par l'écriture du profil (`index.ts`).
 */

/**
 * OUVERT (lot 149, demande du client du 20 novembre 2026) : la fonction
 * `activationChauffeurEmail` est déployée et liée au secret `RESEND_API_KEY`
 * de Secret Manager, créé par le client. Avant tout déploiement, la
 * publication vérifie que ce secret existe et a la forme d'une clé Resend,
 * ainsi que les droits du premier déclencheur Firestore
 * (`scripts/controle_email_activation.sh`) ; sinon elle s'arrête sans rien
 * déployer. Fermé (`false`) : la fonction n'est pas déployée et aucun secret
 * n'est demandé. Ne changer que cette ligne : la CI la lit telle quelle.
 */
export const EMAIL_ACTIVATION_CHAUFFEUR: boolean = true;

/** Nom du secret dans Secret Manager (projet `sprint-vtc`). */
export const NOM_SECRET_RESEND = 'RESEND_API_KEY';

/** Expéditeur : le domaine officiel, vérifié chez Resend. */
export const EXPEDITEUR = 'SPRINT <contact@sprintvtc.sn>';

export const URL_APP = 'https://sprint-vtc.web.app';
export const URL_ANDROID = 'https://sprint-vtc.web.app/android/';

// ---------------------------------------------------------------------
// 1. Le message
// ---------------------------------------------------------------------

/** Couleurs de l'e-mail : noir Onyx et orange (demande du client, 20 novembre 2026). */
export const COULEURS_EMAIL = {
  fond: '#0B0B0C',
  carte: '#151517',
  bord: '#2A2A2E',
  texte: '#F5F5F7',
  discret: '#A1A1A8',
  orange: '#FF7A1A',
  orangeClair: '#FF9A4D',
} as const;

export const SUJET_ACTIVATION = 'Bienvenue chez SPRINT : votre compte chauffeur est activé';

const echapper = (texte: string) =>
  texte.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

/**
 * Prénom à afficher : le prénom du profil, sinon le premier mot du nom ; `null`
 * si rien d'exploitable. Borné et nettoyé (les règles limitent déjà ces champs,
 * mais un profil ancien ou écrit par l'Admin n'est jamais cru sur parole).
 */
export function prenomAffiche(profil: Record<string, unknown>): string | null {
  const brut = [profil.prenom, typeof profil.nom === 'string' ? profil.nom.trim().split(/\s+/)[0] : undefined].find(
    (v): v is string => typeof v === 'string' && v.trim() !== '',
  );
  if (!brut) return null;
  // eslint-disable-next-line no-control-regex
  const propre = brut.replace(/[\u0000-\u001F\u007F]/g, '').trim().slice(0, 40);
  return propre === '' ? null : propre;
}

export interface ModeleCourriel {
  sujet: string;
  texte: string;
  html: string;
}

const ETAPES = [
  'Ouvrez l\'application SPRINT et connectez-vous avec votre e-mail et votre mot de passe.',
  'Autorisez la localisation quand l\'application la demande : elle sert à vous proposer les courses proches.',
  'Passez « En ligne » : vos premières courses arriveront dès qu\'un client en commande une près de vous.',
];

export function modeleActivationChauffeur(prenom: string | null): ModeleCourriel {
  const c = COULEURS_EMAIL;
  const titre = prenom ? `Félicitations ${prenom}, votre compte chauffeur est activé` : 'Félicitations, votre compte chauffeur est activé';
  const accroche = 'Votre dossier a été vérifié par l\'équipe du Groupe Santine. Vous faites désormais partie des chauffeurs SPRINT.';
  const pied = `Une question ? Répondez à cet e-mail ou écrivez à ${ADRESSE_CONTACT}.`;
  const police = 'font-family:Arial,Helvetica,sans-serif;';

  const etapes = ETAPES.map(
    (e, i) =>
      '<tr>' +
      `<td width="32" valign="top" style="padding:0 0 14px"><div style="width:24px;height:24px;border-radius:12px;background:${c.orange};color:${c.fond};${police}font-size:13px;font-weight:800;line-height:24px;text-align:center">${i + 1}</div></td>` +
      `<td valign="top" style="padding:2px 0 14px;${police}font-size:14px;line-height:1.55;color:${c.texte}">${echapper(e)}</td>` +
      '</tr>',
  ).join('');

  const html =
    '<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<meta name="color-scheme" content="dark"><meta name="supported-color-schemes" content="dark">' +
    `<title>${echapper(SUJET_ACTIVATION)}</title></head>` +
    `<body style="margin:0;padding:0;background:${c.fond}" bgcolor="${c.fond}">` +
    `<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:${c.fond}">${echapper(accroche)}</div>` +
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" bgcolor="${c.fond}" style="background:${c.fond}"><tr><td align="center" style="padding:28px 12px">` +
    '<table role="presentation" width="560" cellpadding="0" cellspacing="0" style="width:100%;max-width:560px">' +
    `<tr><td style="padding:0 6px 16px;${police}font-size:14px;font-weight:800;letter-spacing:5px;color:${c.orange}">SPRINT</td></tr>` +
    `<tr><td bgcolor="${c.carte}" style="background:${c.carte};border:1px solid ${c.bord};border-radius:20px;padding:34px 30px">` +
    `<div style="height:4px;width:56px;border-radius:2px;background:${c.orange};margin:0 0 22px"></div>` +
    `<h1 style="margin:0 0 14px;${police}font-size:25px;line-height:1.25;font-weight:800;color:${c.texte}">${echapper(titre)}</h1>` +
    `<p style="margin:0 0 24px;${police}font-size:15px;line-height:1.6;color:${c.discret}">${echapper(accroche)}</p>` +
    `<p style="margin:0 0 14px;${police}font-size:13px;font-weight:800;letter-spacing:1px;text-transform:uppercase;color:${c.orangeClair}">Pour recevoir vos premières courses</p>` +
    `<table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 14px">${etapes}</table>` +
    `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:8px 0 22px"><tr><td bgcolor="${c.orange}" style="background:${c.orange};border-radius:14px">` +
    `<a href="${URL_APP}" style="display:inline-block;padding:15px 30px;${police}font-size:15px;font-weight:800;color:${c.fond};text-decoration:none">Ouvrir SPRINT</a>` +
    '</td></tr></table>' +
    `<p style="margin:0;${police}font-size:12.5px;line-height:1.6;color:${c.discret}">Sur Android, installez l\'application depuis <a href="${URL_ANDROID}" style="color:${c.orangeClair};text-decoration:underline">${URL_ANDROID.replace('https://', '')}</a>. Sur iPhone, ouvrez ${URL_APP.replace('https://', '')} dans Safari, puis « Partager » et « Sur l\'écran d\'accueil ».</p>` +
    '</td></tr>' +
    `<tr><td style="padding:20px 6px 0;${police}font-size:12px;line-height:1.6;color:${c.discret}">${echapper(pied)}<br>SPRINT · Groupe Santine · Dakar, Thiès, Mbour</td></tr>` +
    '</table></td></tr></table></body></html>';

  const texte = [
    titre,
    '',
    accroche,
    '',
    'Pour recevoir vos premières courses :',
    ...ETAPES.map((e, i) => `${i + 1}. ${e}`),
    '',
    `Ouvrir SPRINT : ${URL_APP}`,
    `Application Android : ${URL_ANDROID}`,
    '',
    pied,
    'SPRINT · Groupe Santine · Dakar, Thiès, Mbour',
  ].join('\n');

  return { sujet: SUJET_ACTIVATION, texte, html };
}

// ---------------------------------------------------------------------
// 2. Quand l'envoyer
// ---------------------------------------------------------------------

/** Un chauffeur dont le dossier VIENT d'être approuvé (et non qui l'était déjà). */
export function approbationChauffeur(avant: Record<string, unknown> | undefined, apres: Record<string, unknown> | undefined): boolean {
  return apres?.role === 'conducteur' && apres.statutValidation === 'valide' && avant?.statutValidation !== 'valide';
}

/** Adresse du compte, lue chez Firebase Auth, SEULEMENT si elle est vérifiée. */
export interface ComptesEmail {
  adresseVerifiee(uid: string): Promise<string | null>;
}

export class ComptesFirebaseEmail implements ComptesEmail {
  async adresseVerifiee(uid: string): Promise<string | null> {
    try {
      const compte = await getAuth().getUser(uid);
      return compte.emailVerified && compte.email ? compte.email : null;
    } catch {
      // Compte supprimé entre-temps : rien à envoyer.
      return null;
    }
  }
}

export type RaisonSansEnvoi = 'pas_une_approbation' | 'deja_envoye' | 'compte_bloque' | 'dossier_non_valide' | 'email_non_verifie' | 'echec';

export type ResultatActivation = { envoye: true; id: string } | { envoye: false; raison: RaisonSansEnvoi; code?: string };

export interface DependancesActivation {
  db: Firestore;
  comptes: ComptesEmail;
  envoi: EnvoiCourriel;
}

/**
 * Envoie l'e-mail d'activation d'un chauffeur dont le dossier vient d'être
 * approuvé. Sûr à rejouer (Firestore livre un événement au moins une fois) :
 *
 * - la décision se prend sur le profil RELU, pas sur l'événement (un dossier
 *   rejeté depuis ne reçoit rien) ;
 * - `users/{uid}.emailActivationEnvoyeLe` marque l'envoi (écrit par le
 *   serveur seul : les règles interdisent au client de l'écrire) ;
 * - Resend refuse un doublon pendant 24 h grâce à la clé d'idempotence ;
 * - l'adresse est celle de Firebase Auth, et seulement si elle est vérifiée ;
 * - un compte suspendu ou banni ne reçoit rien ;
 * - un échec n'est jamais une erreur du déclencheur : il est rendu (code sans
 *   secret) pour être consigné, et rien n'est marqué envoyé.
 */
export async function envoyerEmailActivation(
  dependances: DependancesActivation,
  uid: string,
  avant: Record<string, unknown> | undefined,
  apres: Record<string, unknown> | undefined,
): Promise<ResultatActivation> {
  if (!approbationChauffeur(avant, apres)) return { envoye: false, raison: 'pas_une_approbation' };

  const reference = dependances.db.collection('users').doc(uid);
  const profil = (await reference.get()).data() ?? {};
  if (profil.statutValidation !== 'valide' || profil.role !== 'conducteur') return { envoye: false, raison: 'dossier_non_valide' };
  if (profil.emailActivationEnvoyeLe) return { envoye: false, raison: 'deja_envoye' };
  if (profil.statutCompte === 'suspendu' || profil.statutCompte === 'banni') return { envoye: false, raison: 'compte_bloque' };

  const adresse = await dependances.comptes.adresseVerifiee(uid);
  if (!adresse) return { envoye: false, raison: 'email_non_verifie' };

  const modele = modeleActivationChauffeur(prenomAffiche(profil));
  const courriel: CourrielResend = {
    from: EXPEDITEUR,
    to: [adresse],
    subject: modele.sujet,
    html: modele.html,
    text: modele.texte,
    reply_to: ADRESSE_CONTACT,
  };

  let id: string;
  try {
    ({ id } = await dependances.envoi.envoyer(courriel, `activation-chauffeur-${uid}`));
  } catch (e) {
    return { envoye: false, raison: 'echec', code: e instanceof ErreurResend ? e.code : 'resend/inconnu' };
  }

  // Marque l'envoi. Si cette écriture échoue, l'e-mail est parti : la clé
  // d'idempotence empêchera un doublon à la prochaine livraison de l'événement.
  try {
    await reference.update({ emailActivationEnvoyeLe: FieldValue.serverTimestamp(), emailActivationId: id });
  } catch {
    // Sans conséquence pour le destinataire.
  }
  return { envoye: true, id };
}
