import 'distance_utils.dart';

/// Grille de prix d'une course, selon son point de départ : celle de Dakar, ou
/// celle de la province (Thiès, Mbour, motos « Jakarta »).
enum ZoneTarifaire { dakar, province }

/// Une ville de province : un départ à moins de [rayonKm] de son centre est
/// tarifé « province ».
class VilleProvince {
  const VilleProvince({required this.nom, required this.latitude, required this.longitude, required this.rayonKm});

  final String nom;
  final double latitude;
  final double longitude;
  final double rayonKm;
}

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

  /// Les villes qui ont leur propre grille de prix. Tout le reste, Dakar et sa
  /// banlieue comprises, a la grille de Dakar. Mêmes villes et mêmes rayons que
  /// `functions/src/zone.ts` (un test vérifie qu'ils restent identiques) ; les
  /// deux cercles ne se touchent pas (Thiès et Mbour sont à environ 41 km).
  static const List<VilleProvince> villesProvince = [
    VilleProvince(nom: 'Thiès', latitude: 14.7910, longitude: -16.9359, rayonKm: 15),
    // 20 km : Saly, la Somone, Nianing et Ngaparou sont comprises.
    VilleProvince(nom: 'Mbour', latitude: 14.4196, longitude: -16.9640, rayonKm: 20),
  ];

  /// Grille de prix d'une course dont le départ est en ([latitude], [longitude]).
  static ZoneTarifaire zoneTarifaire(double latitude, double longitude) {
    for (final ville in villesProvince) {
      final distance = DistanceUtils.distanceKm(
        latDepart: ville.latitude,
        lngDepart: ville.longitude,
        latArrivee: latitude,
        lngArrivee: longitude,
      );
      if (distance <= ville.rayonKm) return ZoneTarifaire.province;
    }
    return ZoneTarifaire.dakar;
  }
}
