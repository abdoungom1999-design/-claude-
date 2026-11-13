import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Moyens de paiement des courses et des recharges du portefeuille.
 *
 * Orange Money est CONNU (l'historique des courses et des recharges peut
 * en contenir) et son fournisseur réel est branché (`paiement_orange.ts`,
 * jamais le faux opérateur), mais il n'est accepté que selon
 * [ACCES_ORANGE_MONEY].
 *
 * Wave est CONNU, mais son fournisseur est encore le faux Wave (`simulation`,
 * `fournisseurs.ts`) : il n'est accepté que des comptes de test, tant que
 * [WAVE_REEL] est faux.
 */
export const METHODES_CONNUES = ['WAVE', 'ORANGE_MONEY', 'PORTEFEUILLE'] as const;
export type Methode = (typeof METHODES_CONNUES)[number];

/**
 * Le vrai Wave est-il branché ? Tant qu'il ne l'est pas, « Wave » est le faux
 * Wave : aucune somme n'est débitée. Décision du client (13 novembre 2026) : le
 * faux Wave est cloisonné aux COMPTES DE TEST (les comptes clients marqués par
 * un Admin, `testeurOrangeMoney`, voir [AccesOrangeMoney]) et tout ce qu'il
 * produit est marqué « argent de test » (`argent_reel.ts`), jamais compté dans la
 * comptabilité. Les autres clients ne le voient pas et le serveur le refuse.
 *
 * Ne passe à `true` qu'avec le go du client, quand le vrai Wave est branché
 * (`FournisseurWave`, clés marchandes dans Secret Manager, `fournisseur()` de
 * `index.ts`) : seul alors Wave est ouvert à tous. Même réglage, en même temps,
 * dans l'app (`waveReel`, lib/core/widgets/payment_method_selector.dart) : un
 * test vérifie qu'ils sont d'accord.
 */
export const WAVE_REEL: boolean = false;

/**
 * Qui peut payer avec Orange Money (décisions du client, 29 octobre 2026) :
 * - `ferme` : personne ; aucun secret d'Orange n'est déclaré ni lu ;
 * - `testeurs` : seulement les comptes clients marqués « Testeur Orange
 *   Money » par un Admin (champ `testeurOrangeMoney` du profil, posé par
 *   `definirTesteurOrangeMoney`), pour l'essai réel de bout en bout ; les
 *   autres clients ne voient rien ;
 * - `tous` : tous les clients (ouverture officielle).
 */
export type AccesOrangeMoney = 'ferme' | 'testeurs' | 'tous';

/**
 * Réglage en service. Ne change qu'avec le go du client, en même temps que
 * son jumeau dans l'app (`accesOrangeMoney`,
 * lib/core/widgets/payment_method_selector.dart) : un test vérifie qu'ils
 * sont d'accord, et la publication lit cette ligne telle quelle.
 */
export const ACCES_ORANGE_MONEY: AccesOrangeMoney = 'testeurs';

/**
 * Où Orange Money encaisse :
 * - `bacASable` : api.sandbox.orange-sonatel.com, données de test, aucun
 *   argent réel (et aucun moyen d'y payer depuis Max It : support d'Orange,
 *   30 octobre 2026) ;
 * - `production` : api.orange-sonatel.com, argent réel, versé sur le compte
 *   marchand de Groupe Santine.
 * Chaque environnement a ses propres identifiants et sa propre clé de
 * notification (`SECRETS_ORANGE_MONEY`, paiement_orange.ts).
 */
export type EnvironnementOrangeMoney = 'bacASable' | 'production';

/**
 * Réglage en service. Ne change qu'avec le go du client, en même temps que
 * son jumeau dans l'app (`environnementOrangeMoney`, même fichier que
 * `accesOrangeMoney`) : un test vérifie qu'ils sont d'accord, et la
 * publication lit cette ligne telle quelle (secrets à vérifier).
 */
export const ENVIRONNEMENT_ORANGE_MONEY: EnvironnementOrangeMoney = 'production';

/** Orange Money accepté pour ce client ([testeur] : compte marqué par un Admin). */
export function orangeMoneyPour(testeur: boolean, acces: AccesOrangeMoney = ACCES_ORANGE_MONEY): boolean {
  return acces === 'tous' || (acces === 'testeurs' && testeur);
}

/** Wave accepté pour ce client : le vrai Wave pour tous, le faux Wave pour les seuls comptes de test. */
export function wavePour(testeur: boolean, waveReel: boolean = WAVE_REEL): boolean {
  return waveReel || testeur;
}

/**
 * Moyens acceptés pour un nouveau paiement de ce client. Un client ordinaire
 * (ni testeur, Wave simulé) n'a que son solde Sprint : le mobile money s'ouvre à
 * lui avec Orange Money pour tous ou le vrai Wave, sur un nouveau go du client.
 */
export function methodesPour(
  testeur: boolean,
  acces: AccesOrangeMoney = ACCES_ORANGE_MONEY,
  waveReel: boolean = WAVE_REEL,
): readonly Methode[] {
  return [
    ...(wavePour(testeur, waveReel) ? (['WAVE'] as const) : []),
    ...(orangeMoneyPour(testeur, acces) ? (['ORANGE_MONEY'] as const) : []),
    'PORTEFEUILLE',
  ];
}

/** Moyens qui rechargent le portefeuille de ce client : le mobile money accepté (jamais le solde lui-même). */
export function methodesRechargePour(
  testeur: boolean,
  acces: AccesOrangeMoney = ACCES_ORANGE_MONEY,
  waveReel: boolean = WAVE_REEL,
): readonly Methode[] {
  return methodesPour(testeur, acces, waveReel).filter((m) => m !== 'PORTEFEUILLE');
}

/** Moyens acceptés aujourd'hui pour un client ordinaire (pas testeur). */
export const METHODES_ACTIVES: readonly Methode[] = methodesPour(false);

/** Moyens qui rechargent le portefeuille d'un client ordinaire. */
export const METHODES_RECHARGE: readonly Methode[] = methodesRechargePour(false);

const LIBELLES: Record<Methode, string> = {
  WAVE: 'Wave',
  ORANGE_MONEY: 'Orange Money',
  PORTEFEUILLE: 'votre solde Sprint',
};

/**
 * Valide le moyen de paiement reçu. Un moyen connu mais fermé à ce compte
 * (Orange Money, ou Wave tant qu'il est simulé) est une précondition non
 * remplie, avec un message qui indique quoi choisir à la place ; sans aucun
 * moyen ouvert (recharge d'un client ordinaire), il dit que le paiement en ligne
 * n'est pas encore ouvert. Toute autre valeur est un argument invalide.
 */
export function verifierMethode(valeur: unknown, autorisees: readonly Methode[], action: 'payer' | 'recharger'): Methode {
  const connue = METHODES_CONNUES.find((m) => m === valeur);
  const choix = autorisees.map((m) => LIBELLES[m]).join(' ou ');
  if (connue !== undefined && autorisees.includes(connue)) return connue;
  if (connue !== undefined && autorisees.length === 0) {
    throw new HttpsError('failed-precondition', "Le paiement en ligne n'est pas encore ouvert à votre compte.", {
      raison: 'methode_indisponible',
    });
  }
  if (connue === 'ORANGE_MONEY' || connue === 'WAVE') {
    throw new HttpsError(
      'failed-precondition',
      `${LIBELLES[connue]} n'est pas encore disponible : ${action === 'payer' ? 'payez' : 'rechargez'} avec ${choix}.`,
      { raison: 'methode_indisponible' },
    );
  }
  throw new HttpsError(
    'invalid-argument',
    autorisees.length === 0
      ? 'Mode de paiement invalide.'
      : `Mode de paiement invalide : ${autorisees.length === 1 ? `${choix} uniquement` : choix}.`,
  );
}
