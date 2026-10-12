import { distanceKm, type Point, type ZoneTarifaire } from './tarification';

/**
 * Zone où Sprint est ouvert : Dakar, Thiès et Mbour, avec les routes qui les
 * relient (un seul rectangle, en degrés).
 *
 * Ce n'est qu'une aide à la saisie, pas une barrière : le rectangle est donné
 * à Google Places comme zone prioritaire pour l'autocomplétion des adresses
 * (voir `google.ts`), et rien ne refuse une commande hors de ce rectangle.
 * L'app a les mêmes chiffres pour la recherche d'adresses de secours
 * (`lib/core/maps/zone_service.dart`) : un test vérifie qu'ils restent
 * identiques.
 *
 * Pour étendre la zone (Joal, Tivaouane...), changer ces quatre bords ET ceux
 * de l'app.
 */
export const ZONE_SERVICE = {
  /** L'océan, à l'ouest de la pointe des Almadies. */
  ouest: -17.63,
  /** Au-delà de la sortie est de Thiès. */
  est: -16.75,
  /** Au-dessus du lac Rose et de Thiès. */
  nord: 14.9,
  /** Sous Saly et Nianing, avant Joal. */
  sud: 14.3,
} as const;

/** Le rectangle au format « locationBias » de Google Places (coins sud-ouest et nord-est). */
export const BIAIS_ZONE = {
  rectangle: {
    low: { latitude: ZONE_SERVICE.sud, longitude: ZONE_SERVICE.ouest },
    high: { latitude: ZONE_SERVICE.nord, longitude: ZONE_SERVICE.est },
  },
} as const;

/**
 * Villes de province, qui ont leur propre grille de prix (voir
 * `tarification.ts`). Un départ à moins de `rayonKm` du centre d'une de ces
 * villes est tarifé « province » ; tout le reste, Dakar et sa banlieue
 * comprises, garde la grille de Dakar. Les deux cercles ne se touchent pas
 * (Thiès et Mbour sont à environ 41 km l'une de l'autre).
 */
export const VILLES_PROVINCE = [
  { nom: 'Thiès', centre: { latitude: 14.791, longitude: -16.9359 }, rayonKm: 15 },
  /** 20 km : Saly, la Somone, Nianing et Ngaparou sont comprises. */
  { nom: 'Mbour', centre: { latitude: 14.4196, longitude: -16.964 }, rayonKm: 20 },
] as const;

/** Grille de prix d'une course, selon son point de départ. */
export function zoneTarifaire(depart: Point): ZoneTarifaire {
  return VILLES_PROVINCE.some((ville) => distanceKm(ville.centre, depart) <= ville.rayonKm) ? 'PROVINCE' : 'DAKAR';
}
