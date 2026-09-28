/**
 * Moteur de tarification de Sprint : seule source de vérité du prix
 * d'une course. Même grille et mêmes calculs que l'estimation affichée
 * par l'app en mode démo (`DemoData.estimerPrix` et
 * `DistanceUtils.distanceRouteEstimeeKm` côté Flutter).
 *
 * Grille alignée sur le marché dakarois de la moto-taxi : prise en
 * charge + kilomètres, sans facturation à la minute ; majoration x1,2 en
 * heure de pointe et la nuit ; prix arrondi à la centaine, minimum
 * 1 000 FCFA. Ex. : 15 km hors pointe = 300 + 15 x 200 = 3 300 FCFA.
 */

export type TypeCourse = 'PASSAGER' | 'COLIS';

export const TYPES_COURSE: readonly TypeCourse[] = ['PASSAGER', 'COLIS'];

export interface Point {
  latitude: number;
  longitude: number;
}

interface Tarifs {
  prisEnCharge: number;
  parKm: number;
  parMinute: number;
  prixMinimum: number;
}

const TARIFS: Record<TypeCourse, Tarifs> = {
  PASSAGER: { prisEnCharge: 300, parKm: 200, parMinute: 0, prixMinimum: 1000 },
  COLIS: { prisEnCharge: 300, parKm: 200, parMinute: 0, prixMinimum: 1000 },
};

/** Durée affichée au client ; facturée seulement si `parMinute` > 0. */
const VITESSE_MOYENNE_KMH = 22;

const MULTIPLICATEUR_MAJORATION = 1.2;

const RAYON_TERRE_KM = 6371.0;

/**
 * Majoration de la distance à vol d'oiseau pour approcher la distance
 * par la route (détours, sens uniques), tant qu'aucun calcul
 * d'itinéraire réel n'est branché.
 */
export const COEFFICIENT_DETOUR = 1.1;

export interface EstimationPrix {
  distanceKm: number;
  dureeEstimeeMin: number;
  multiplicateurTrafic: number;
  prixFcfa: number;
  /** "Heure de pointe", "Tarif de nuit" ; `null` sans majoration. */
  motifMajoration: string | null;
}

const versRadians = (degres: number): number => degres * (Math.PI / 180);

/** Distance à vol d'oiseau (formule de Haversine). */
export function distanceKm(depart: Point, arrivee: Point): number {
  const dLat = versRadians(arrivee.latitude - depart.latitude);
  const dLng = versRadians(arrivee.longitude - depart.longitude);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(versRadians(depart.latitude)) *
      Math.cos(versRadians(arrivee.latitude)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return RAYON_TERRE_KM * c;
}

/** Distance estimée par la route : c'est elle qui sert au prix. */
export function distanceRouteEstimeeKm(depart: Point, arrivee: Point): number {
  return distanceKm(depart, arrivee) * COEFFICIENT_DETOUR;
}

/** Dakar est en UTC+0 toute l'année : l'heure UTC est l'heure locale. */
export function motifMajoration(heureUtc: number): string | null {
  if ((heureUtc >= 7 && heureUtc < 10) || (heureUtc >= 17 && heureUtc < 20)) return 'Heure de pointe';
  if (heureUtc >= 22 || heureUtc < 5) return 'Tarif de nuit';
  return null;
}

export function estimerPrix(type: TypeCourse, distanceKmBrut: number, maintenant: Date): EstimationPrix {
  const distance = distanceKmBrut < 0 ? 0 : distanceKmBrut;
  const dureeEstimeeMin = Math.round((distance / VITESSE_MOYENNE_KMH) * 60);
  const tarifs = TARIFS[type];
  const motif = motifMajoration(maintenant.getUTCHours());
  const multiplicateurTrafic = motif === null ? 1.0 : MULTIPLICATEUR_MAJORATION;

  const montantBrut =
    (tarifs.prisEnCharge + distance * tarifs.parKm + dureeEstimeeMin * tarifs.parMinute) * multiplicateurTrafic;
  const prixArrondi = Math.round(montantBrut / 100) * 100;

  return {
    distanceKm: distance,
    dureeEstimeeMin,
    multiplicateurTrafic,
    prixFcfa: Math.max(prixArrondi, tarifs.prixMinimum),
    motifMajoration: motif,
  };
}
