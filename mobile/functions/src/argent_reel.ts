import { Timestamp, type DocumentData } from 'firebase-admin/firestore';
import { FOURNISSEUR_ORANGE } from './fournisseurs';
import { ENVIRONNEMENT_ORANGE_MONEY } from './methodes_paiement';

/**
 * Argent réel ou argent de test : une seule règle, pour tout le serveur.
 *
 * Tant que Wave est simulé (`simulation`, voir `fournisseurs.ts`), un paiement
 * ou une recharge Wave ne débite personne : c'est de l'argent de test. Il ne
 * doit jamais entrer dans la comptabilité (décision du client, 13 novembre
 * 2026 : le faux Wave est cloisonné aux comptes de test, voir `methodes_paiement.ts`,
 * et tout ce qu'il produit est marqué « argent de test »).
 *
 * Ce module ne dépend d'aucun autre module de paiement : le portefeuille, les
 * retraits, les commandes et le radar s'en servent sans se rappeler les uns les
 * autres.
 */

/**
 * Orange Money encaisse de l'argent réel depuis la publication 114 (fonctions
 * déployées le 2 novembre 2026 entre 9 h 41 et 9 h 43, heure de Dakar = UTC) ;
 * avant : bac à sable, argent de test. Jumeau dans l'app
 * (`debutArgentReelOrange`, lib/features/finances/data/argent_de_test.dart) :
 * un test vérifie qu'ils sont d'accord.
 */
export const DEBUT_ARGENT_REEL_ORANGE = new Date('2026-11-02T09:43:00Z');

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

/** Date d'un champ Firestore horodaté ; `null` s'il n'en est pas un. */
export const dateDe = (valeur: unknown): Date | null => (valeur instanceof Timestamp ? valeur.toDate() : null);

/**
 * La commande ou la recharge [document] est-elle en argent de test ? La marque
 * `argentDeTest`, posée à sa création, fait foi. Une commande ou une recharge
 * créée avant ce marquage (un paiement en cours au moment du déploiement) est
 * jugée sur son fournisseur et sa date, par [encaissementReel] : jamais de
 * l'argent réel par défaut.
 */
export function argentDeTestDe(document: DocumentData): boolean {
  if (typeof document.argentDeTest === 'boolean') return document.argentDeTest;
  return !encaissementReel(document.fournisseur, dateDe(document.creeLe));
}
