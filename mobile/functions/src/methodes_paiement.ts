import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Moyens de paiement des courses et des recharges du portefeuille.
 *
 * Orange Money est CONNU (l'historique des courses et des recharges peut
 * en contenir) et son fournisseur réel est branché (`paiement_orange.ts`,
 * jamais le faux opérateur), mais il reste REFUSÉ pour tout nouveau
 * paiement tant que [ORANGE_MONEY_OUVERT] est faux.
 */
export const METHODES_CONNUES = ['WAVE', 'ORANGE_MONEY', 'PORTEFEUILLE'] as const;
export type Methode = (typeof METHODES_CONNUES)[number];

/**
 * Orange Money ouvert aux clients. Ne passe à `true` qu'avec le go du client
 * (essai complet du bac à sable validé ensemble, identifiants de production
 * dans Secret Manager), en même temps que son jumeau dans l'app
 * (`orangeMoneyOuvert`, lib/core/widgets/payment_method_selector.dart) : un
 * test vérifie qu'ils sont d'accord.
 */
export const ORANGE_MONEY_OUVERT: boolean = false;

/** Moyens acceptés aujourd'hui pour un nouveau paiement. */
export const METHODES_ACTIVES: readonly Methode[] = ORANGE_MONEY_OUVERT
  ? ['WAVE', 'ORANGE_MONEY', 'PORTEFEUILLE']
  : ['WAVE', 'PORTEFEUILLE'];

/** Moyens qui rechargent le portefeuille : le mobile money actif (jamais le solde lui-même). */
export const METHODES_RECHARGE: readonly Methode[] = METHODES_ACTIVES.filter((m) => m !== 'PORTEFEUILLE');

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
