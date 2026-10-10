import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'distance_utils.dart';

/// Position d'un point par rapport à un tracé (voir [TraceUtils.projeter]).
class ProjectionTrace {
  const ProjectionTrace({required this.segment, required this.point, required this.ecartM, required this.resteM});

  /// Indice du point du tracé qui ouvre le segment le plus proche.
  final int segment;

  /// Point du tracé le plus proche de la position.
  final LatLng point;

  /// Distance entre la position et le tracé, en mètres : grande, on a quitté l'itinéraire.
  final double ecartM;

  /// Distance qui reste à parcourir sur le tracé, de [point] jusqu'à son extrémité, en mètres.
  final double resteM;
}

/// Calculs sur un itinéraire : décodage du format « encoded polyline » de
/// Google, longueur, et position d'un point sur la ligne (distance restante).
abstract final class TraceUtils {
  /// Mètres par degré de latitude (rayon moyen de la Terre).
  static const _metresParDegre = 6371000 * math.pi / 180;

  /// Décode un tracé « encoded polyline » de Google (points à 5 décimales).
  /// Lève une [FormatException] si le texte est tronqué ou sort du globe.
  static List<LatLng> decoder(String encode) {
    final points = <LatLng>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;

    // De l'arithmétique, jamais d'opérateurs binaires (« ~ », « << », « >> », « | ») :
    // sur le web (la PWA de l'iPhone), ils ne travaillent que sur 32 bits et « ~ » rend un
    // entier non signé. Chaque coordonnée négative (toutes les longitudes de Dakar) sortait
    // alors du globe et l'itinéraire du chauffeur retombait sur la ligne droite. Les tests
    // de la machine virtuelle ne le voyaient pas : voir aussi `trace_utils_test.dart`.
    int lireValeur() {
      var resultat = 0;
      var poids = 1;
      int octet;
      do {
        if (index >= encode.length) throw const FormatException('Tracé tronqué.');
        octet = encode.codeUnitAt(index++) - 63;
        if (octet < 0) throw const FormatException('Caractère de tracé invalide.');
        resultat += (octet % 32) * poids;
        poids *= 32;
      } while (octet >= 32);
      // Pair : positif ; impair : négatif (valeur = -(résultat + 1) / 2).
      return resultat.isOdd ? -((resultat + 1) ~/ 2) : resultat ~/ 2;
    }

    while (index < encode.length) {
      latitude += lireValeur();
      longitude += lireValeur();
      final lat = latitude / 1e5;
      final lng = longitude / 1e5;
      if (lat.abs() > 90 || lng.abs() > 180) throw const FormatException('Coordonnées du tracé hors du globe.');
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  /// Distance à vol d'oiseau entre deux points, en mètres.
  static double distanceM(LatLng a, LatLng b) =>
      DistanceUtils.distanceKm(
        latDepart: a.latitude,
        lngDepart: a.longitude,
        latArrivee: b.latitude,
        lngArrivee: b.longitude,
      ) *
      1000;

  /// Longueur d'un tracé, en mètres.
  static double longueurM(List<LatLng> trace) {
    var total = 0.0;
    for (var i = 1; i < trace.length; i++) {
      total += distanceM(trace[i - 1], trace[i]);
    }
    return total;
  }

  /// Où se trouve [position] sur [trace] : point du tracé le plus proche, écart
  /// avec le tracé et distance qu'il reste à parcourir. Ne cherche qu'à partir
  /// du segment [depuisSegment] : un chauffeur avance sur son itinéraire, ce
  /// qui évite de se raccrocher à un tronçon voisin quand la route fait demi-tour.
  /// `null` si le tracé est vide.
  static ProjectionTrace? projeter(List<LatLng> trace, LatLng position, {int depuisSegment = 0}) {
    if (trace.isEmpty) return null;
    if (trace.length == 1) {
      return ProjectionTrace(segment: 0, point: trace.first, ecartM: distanceM(position, trace.first), resteM: 0);
    }

    // Plan local centré sur la position : à l'échelle d'une ville, une
    // projection plate donne des écarts justes au mètre près.
    final echelleLng = math.cos(position.latitude * math.pi / 180);
    (double, double) plan(LatLng p) => (
          (p.longitude - position.longitude) * echelleLng * _metresParDegre,
          (p.latitude - position.latitude) * _metresParDegre,
        );

    final premier = depuisSegment.clamp(0, trace.length - 2);
    var meilleurSegment = premier;
    var meilleurT = 0.0;
    var meilleurEcart = double.infinity;
    for (var i = premier; i < trace.length - 1; i++) {
      final (ax, ay) = plan(trace[i]);
      final (bx, by) = plan(trace[i + 1]);
      final dx = bx - ax;
      final dy = by - ay;
      final longueurCarre = dx * dx + dy * dy;
      // Projection de l'origine (la position) sur le segment, bornée à ses extrémités.
      final t = longueurCarre == 0 ? 0.0 : (-(ax * dx + ay * dy) / longueurCarre).clamp(0.0, 1.0);
      final px = ax + t * dx;
      final py = ay + t * dy;
      final ecart = math.sqrt(px * px + py * py);
      if (ecart < meilleurEcart) {
        meilleurEcart = ecart;
        meilleurSegment = i;
        meilleurT = t;
      }
    }

    final a = trace[meilleurSegment];
    final b = trace[meilleurSegment + 1];
    final point = LatLng(
      a.latitude + (b.latitude - a.latitude) * meilleurT,
      a.longitude + (b.longitude - a.longitude) * meilleurT,
    );
    var reste = distanceM(point, b);
    for (var i = meilleurSegment + 1; i < trace.length - 1; i++) {
      reste += distanceM(trace[i], trace[i + 1]);
    }
    return ProjectionTrace(segment: meilleurSegment, point: point, ecartM: meilleurEcart, resteM: reste);
  }

  /// Ce qui reste du tracé à partir de la projection : le point du tracé le
  /// plus proche, puis tous les points suivants.
  static List<LatLng> restant(List<LatLng> trace, ProjectionTrace projection) =>
      [projection.point, ...trace.sublist(projection.segment + 1)];
}
