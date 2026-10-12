import '../../../core/maps/distance_utils.dart';
import '../../courses/data/course_service.dart';
import '../../courses/data/position_chauffeur.dart';

/// Un chauffeur n'est alerté que des courses à moins de [rayonKm] de lui
/// (décision du client, 12 octobre 2026) : une course à Thiès ne fait pas
/// sonner les chauffeurs de Dakar, ni l'inverse.
///
/// Même règle que côté serveur pour les notifications (`RAYON_ALERTE_KM` et
/// `FRAICHEUR_POSITION_ALERTE_MS` dans `functions/src/notifications.ts` : un
/// test vérifie qu'ils restent identiques).
abstract final class RayonAlertes {
  /// Distance maximale entre le chauffeur et le départ de la course.
  static const rayonKm = 30.0;

  /// Au-delà de cet âge, la dernière position du chauffeur n'est plus fiable.
  static const fraicheurPosition = Duration(minutes: 30);

  /// La course doit-elle être proposée à ce chauffeur ?
  ///
  /// Oui si on ne sait pas où il est (aucune position, ou trop ancienne) ou si
  /// la course n'a pas de coordonnées (course ancienne) : comme avant, mieux
  /// vaut une proposition de trop qu'une course manquée. Le départ d'une course
  /// en attente n'est connu qu'à ~150 m près (masquage) : sans importance pour
  /// un rayon de 30 km.
  static bool proposer(CourseFirestore course, PositionChauffeurDirect? position, {DateTime? maintenant}) {
    final depart = course.points;
    final releveLe = position?.majLe;
    if (depart == null || position == null || releveLe == null) return true;
    if ((maintenant ?? DateTime.now()).difference(releveLe) > fraicheurPosition) return true;
    final distance = DistanceUtils.distanceKm(
      latDepart: position.latitude,
      lngDepart: position.longitude,
      latArrivee: depart.latitudeDepart,
      lngArrivee: depart.longitudeDepart,
    );
    return distance <= rayonKm;
  }
}
