/// Zone où Sprint est ouvert : Dakar, Thiès et Mbour, avec les routes qui les
/// relient (un seul rectangle).
///
/// Ce n'est qu'une aide à la saisie, pas une barrière : la recherche d'adresses
/// de secours (OpenStreetMap, voir `GeocodingService`) ne cherche que dans ce
/// rectangle, et le serveur le donne aussi à Google Places comme zone
/// prioritaire (`functions/src/zone.ts` : mêmes chiffres, un test vérifie
/// qu'ils restent identiques). Rien ne refuse une commande hors du rectangle.
///
/// Pour étendre la zone (Joal, Tivaouane...), changer ces quatre bords ET ceux
/// de `functions/src/zone.ts`.
class ZoneDeService {
  const ZoneDeService._();

  /// Bord ouest : l'océan, à l'ouest de la pointe des Almadies.
  static const double ouest = -17.63;

  /// Bord est : au-delà de la sortie est de Thiès.
  static const double est = -16.75;

  /// Bord nord : au-dessus du lac Rose et de Thiès.
  static const double nord = 14.90;

  /// Bord sud : sous Saly et Nianing, avant Joal.
  static const double sud = 14.30;

  /// Le rectangle au format « viewbox » de Nominatim : gauche, haut, droite, bas.
  static const String viewbox = '$ouest,$nord,$est,$sud';
}
