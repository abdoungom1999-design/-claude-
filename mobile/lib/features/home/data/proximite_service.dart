import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import '../../../core/firebase/fonctions_cloud.dart';

/// Une moto disponible à proximité, telle que le serveur la décrit :
/// position arrondie à environ 150 m, sans identité.
class MotoProche {
  const MotoProche({required this.position, this.cap});

  final LatLng position;

  /// Direction (degrés, arrondie à 45°), ou `null` si inconnue.
  final double? cap;
}

class Proximite {
  const Proximite({this.motos = const [], this.approcheMinutes});

  static const vide = Proximite();

  final List<MotoProche> motos;

  /// Approche estimée de la moto la plus proche (minutes), ou `null`.
  final int? approcheMinutes;
}

/// Motos disponibles autour d'un point, pour la carte de l'accueil.
abstract class ProximiteService {
  Future<Proximite> chauffeursProches(LatLng autour);
}

/// Service réel : Cloud Function `chauffeursProches` (positions anonymes,
/// arrondies à 150 m par le serveur).
class ProximiteFirebase implements ProximiteService {
  @override
  Future<Proximite> chauffeursProches(LatLng autour) async {
    final r = await FonctionsCloud.appeler('chauffeursProches', {
      'latitude': autour.latitude,
      'longitude': autour.longitude,
    });
    return Proximite(
      motos: [
        for (final c in (r['chauffeurs'] as List? ?? const []).whereType<Map>())
          if (c['latitude'] is num && c['longitude'] is num)
            MotoProche(
              position: LatLng((c['latitude'] as num).toDouble(), (c['longitude'] as num).toDouble()),
              cap: (c['cap'] as num?)?.toDouble(),
            ),
      ],
      approcheMinutes: (r['approcheMinutes'] as num?)?.toInt(),
    );
  }
}

/// Mode démo (sans Firebase) : quelques motos fictives autour du point,
/// toujours aux mêmes endroits pour un même quartier.
class ProximiteDemo implements ProximiteService {
  const ProximiteDemo();

  static const _decalages = [
    (0.0042, -0.0031, 45.0),
    (-0.0036, 0.0048, 180.0),
    (0.0071, 0.0056, 270.0),
    (-0.0064, -0.0052, 90.0),
    (0.0012, 0.0089, 0.0),
    (-0.0091, 0.0017, 315.0),
  ];

  @override
  Future<Proximite> chauffeursProches(LatLng autour) async {
    // Ancré sur une grille d'environ 1 km : les motos ne "suivent" pas la
    // carte quand on la déplace un peu.
    double ancre(double x) => (x * 100).roundToDouble() / 100;
    final base = LatLng(ancre(autour.latitude), ancre(autour.longitude));
    final graine = (base.latitude * 1000).round() ^ (base.longitude * 1000).round();
    final alea = math.Random(graine);
    return Proximite(
      motos: [
        for (final (dLat, dLng, cap) in _decalages)
          MotoProche(
            position: LatLng(base.latitude + dLat + alea.nextDouble() * 0.001, base.longitude + dLng),
            cap: cap,
          ),
      ],
      approcheMinutes: 3,
    );
  }
}
