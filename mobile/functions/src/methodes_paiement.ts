import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Moyens de paiement des courses et des recharges du portefeuille.
 *
 * Orange Money est CONNU (l'historique des courses et des recharges peut
 * en contenir) et son fournisseur réel est branché (`paiement_orange.ts`,
 * jamais le faux opérateur), mais il n'est accepté que selon
 * [ACCES_ORANGE_MONEY].
 */
export const METHODES_CONNUES = ['WAVE', 'ORANGE_MONEY', 'PORTEFEUILLE'] as const;
export type Methode = (typeof METHODES_CONNUES)[number];

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

/** Orange Money accepté pour ce client ([testeur] : compte marqué par un Admin). */
export function orangeMoneyPour(testeur: boolean, acces: AccesOrangeMoney = ACCES_ORANGE_MONEY): boolean {
  return acces === 'tous' || (acces === 'testeurs' && testeur);
}

/** Moyens acceptés pour un nouveau paiement de ce client. */
export function methodesPour(testeur: boolean, acces: AccesOrangeMoney = ACCES_ORANGE_MONEY): readonly Methode[] {
  return orangeMoneyPour(testeur, acces) ? ['WAVE', 'ORANGE_MONEY', 'PORTEFEUILLE'] : ['WAVE', 'PORTEFEUILLE'];
}

/** Moyens qui rechargent le portefeuille de ce client : le mobile money accepté (jamais le solde lui-même). */
export function methodesRechargePour(testeur: boolean, acces: AccesOrangeMoney = ACCES_ORANGE_MONEY): readonly Methode[] {
  return methodesPour(testeur, acces).filter((m) => m !== 'PORTEFEUILLE');
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
 * Valide le moyen de paiement reçu. Un moyen connu mais fermé (Orange
 * Money) est une précondition non remplie, avec un message qui indique quoi
 * choisir à la place ; toute autre valeur est un argument invalide.
 */
export function verifierMethode(valeur: unknown, autorisees: readonly Methode[], action: 'payer' | 'recharger'): Methode {
  const connue = METHODES_CONNUES.find((m) => m === valeur);
  const choix = autorisees.map((m) => LIBELLES[m]).join(' ou ');
  if (connue !== undefined && autorisees.includes(connue)) return connue;
  if (connue === 'ORANGE_MONEY') {
    throw new HttpsError(
      'failed-precondition',
      `Orange Money n'est pas encore disponible : ${action === 'payer' ? 'payez' : 'rechargez'} avec ${choix}.`,
      { raison: 'methode_indisponible' },
    );
  }
  throw new HttpsError(
    'invalid-argument',
    `Mode de paiement invalide : ${autorisees.length === 1 ? `${choix} uniquement` : choix}.`,
  );
}
