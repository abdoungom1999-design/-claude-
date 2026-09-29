import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import type { CalculDistance, DistanceTrajet } from './distances';
import {
  distanceRouteEstimeeKm,
  estimerPrix,
  TYPES_COURSE,
  type EstimationPrix,
  type Point,
  type TypeCourse,
} from './tarification';

/** En dessous, départ et arrivée sont le même lieu (même seuil que l'app). */
export const DISTANCE_MIN_KM = 0.1;

/** Au-delà, la course est hors zone (protection contre les saisies absurdes). */
export const DISTANCE_MAX_KM = 100;

/** 100 % mobile money : la plateforme encaisse chaque course. */
export const METHODES_PAIEMENT = ['WAVE', 'ORANGE_MONEY'] as const;

export interface Trajet {
  type: TypeCourse;
  depart: Point;
  arrivee: Point;
  /** Vol d'oiseau x 1,1 : sert aux contrôles (même lieu, hors zone). */
  distanceKm: number;
}

/** Demande de course envoyée par l'app, avant paiement. */
export interface Demande extends Trajet {
  adresseDepart: string;
  adresseArrivee: string;
  methodePaiement: (typeof METHODES_PAIEMENT)[number];
  prixAttendu: number;
}

function invalide(message: string): HttpsError {
  return new HttpsError('invalid-argument', message);
}

function objet(valeur: unknown): Record<string, unknown> {
  if (typeof valeur !== 'object' || valeur === null || Array.isArray(valeur)) {
    throw invalide('Requête invalide.');
  }
  return valeur as Record<string, unknown>;
}

function point(valeur: unknown, nom: string): Point {
  const p = objet(valeur);
  const { latitude, longitude } = p;
  if (
    typeof latitude !== 'number' ||
    typeof longitude !== 'number' ||
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  ) {
    throw invalide(`Coordonnées de ${nom} invalides.`);
  }
  return { latitude, longitude };
}

function texte(valeur: unknown, nom: string, max: number): string {
  if (typeof valeur !== 'string' || valeur.trim().length === 0 || valeur.length > max) {
    throw invalide(`${nom} invalide.`);
  }
  return valeur.trim();
}

/** Type de course et coordonnées ; la distance est calculée ici. */
export function validerTrajet(donnees: unknown): Trajet {
  const d = objet(donnees);
  if (!TYPES_COURSE.includes(d.type as TypeCourse)) throw invalide('Type de course invalide.');
  const depart = point(d.depart, 'départ');
  const arrivee = point(d.arrivee, 'arrivée');
  const distanceKm = distanceRouteEstimeeKm(depart, arrivee);
  if (distanceKm < DISTANCE_MIN_KM) {
    throw invalide("L'adresse de départ et l'adresse d'arrivée sont identiques.");
  }
  if (distanceKm > DISTANCE_MAX_KM) {
    throw invalide(`Ce trajet dépasse ${DISTANCE_MAX_KM} km : il est hors de la zone desservie.`);
  }
  return { type: d.type as TypeCourse, depart, arrivee, distanceKm };
}

export function validerDemande(donnees: unknown): Demande {
  const trajet = validerTrajet(donnees);
  const d = objet(donnees);
  if (!METHODES_PAIEMENT.includes(d.methodePaiement as Demande['methodePaiement'])) {
    throw invalide('Mode de paiement invalide : Wave ou Orange Money uniquement.');
  }
  const prixAttendu = d.prixAttendu;
  if (typeof prixAttendu !== 'number' || !Number.isInteger(prixAttendu) || prixAttendu <= 0) {
    throw invalide('Prix attendu invalide.');
  }
  return {
    ...trajet,
    adresseDepart: texte(d.adresseDepart, 'Adresse de départ', 300),
    adresseArrivee: texte(d.adresseArrivee, "Adresse d'arrivée", 300),
    methodePaiement: d.methodePaiement as Demande['methodePaiement'],
    prixAttendu,
  };
}

export interface EstimationServeur extends EstimationPrix {
  /** "route" (Google Routes) ou "estimation" (secours). */
  sourceDistance: DistanceTrajet['source'];
}

/**
 * Callable `estimerPrix` : prix affiché au client avant de commander,
 * sur la distance par la route ([calcul]).
 */
export async function estimer(
  calcul: CalculDistance,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
): Promise<EstimationServeur> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous pour estimer un trajet.');
  const trajet = validerTrajet(donnees);
  const distance = await calcul(trajet.depart, trajet.arrivee);
  return { ...estimerPrix(trajet.type, distance.distanceKm, maintenant), sourceDistance: distance.source };
}

/** Client connecté, avec un profil, ni suspendu ni banni. */
export async function verifierClient(db: Firestore, uid: string | undefined): Promise<string> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous pour commander une course.');
  const profil = await db.collection('users').doc(uid).get();
  if (!profil.exists) throw new HttpsError('permission-denied', 'Profil introuvable.');
  const statutCompte = profil.get('statutCompte');
  if (statutCompte === 'suspendu' || statutCompte === 'banni') {
    throw new HttpsError('permission-denied', 'Votre compte ne permet pas de commander une course.');
  }
  return uid;
}

export interface PrixServeur {
  estimation: EstimationPrix;
  distance: DistanceTrajet;
}

/**
 * Prix recalculé par le serveur (même calcul et même cache que
 * l'estimation affichée). S'il diffère de celui que le client a vu
 * (changement de tranche horaire entre-temps), rien n'est fait et le
 * nouveau prix est renvoyé.
 */
export async function prixServeur(calcul: CalculDistance, demande: Demande, maintenant: Date): Promise<PrixServeur> {
  const distance = await calcul(demande.depart, demande.arrivee);
  const estimation = estimerPrix(demande.type, distance.distanceKm, maintenant);
  if (estimation.prixFcfa !== demande.prixAttendu) {
    throw new HttpsError('failed-precondition', 'Le prix de ce trajet a changé.', {
      raison: 'prix-modifie',
      prixFcfa: estimation.prixFcfa,
    });
  }
  return { estimation, distance };
}
