import 'dart:math' as math;

/// Distance approximative entre deux points GPS (formule de Haversine,
/// suffisante pour une estimation de trajet ; ne tient pas compte du
/// réseau routier réel).
class DistanceUtils {
  DistanceUtils._();

  static const _rayonTerreKm = 6371.0;

  static double distanceKm({
    required double latDepart,
    required double lngDepart,
    required double latArrivee,
    required double lngArrivee,
  }) {
    final dLat = _versRadians(latArrivee - latDepart);
    final dLng = _versRadians(lngArrivee - lngDepart);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_versRadians(latDepart)) *
            math.cos(_versRadians(latArrivee)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _rayonTerreKm * c;
  }

  static double _versRadians(double degres) => degres * (math.pi / 180);
}
