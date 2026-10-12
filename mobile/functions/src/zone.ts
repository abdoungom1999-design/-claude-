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
