import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/maps/distance_utils.dart';

/// Dernière position connue d'un chauffeur en ligne
/// (`positions_chauffeurs/{uid}`, publiée par `PositionChauffeurService`),
/// lue par l'Admin (carte en direct) et par le client pendant sa course.
class PositionChauffeurDirect {
  const PositionChauffeurDirect({
    required this.uid,
    required this.latitude,
    required this.longitude,
    required this.majLe,
  });

  final String uid;
  final double latitude;
  final double longitude;

  /// `null` le temps que le serveur horodate le tout premier envoi.
  final DateTime? majLe;

  static PositionChauffeurDirect? depuisDocument(String uid, Map<String, dynamic> donnees) {
    final latitude = donnees['latitude'];
    final longitude = donnees['longitude'];
    if (latitude is! num || longitude is! num) return null;
    final majLe = donnees['majLe'];
    return PositionChauffeurDirect(
      uid: uid,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      majLe: majLe is Timestamp ? majLe.toDate() : null,
    );
  }
}

/// Fraîcheur du signal GPS d'un chauffeur. Le téléphone envoie sa
/// position au moins toutes les 30 s, même à l'arrêt.
enum EtatSignal {
  /// Position reçue il y a moins de 2 minutes.
  actif,

  /// Plus de nouvelles depuis 2 à 30 minutes (écran verrouillé, onglet
  /// fermé, réseau coupé…) : affiché en gris, dernière position connue.
  perdu,

  /// Plus de 30 minutes : le chauffeur n'est plus affiché.
  expire;

  static const delaiPerdu = Duration(minutes: 2);
  static const delaiExpire = Duration(minutes: 30);

  static EtatSignal pour(DateTime? majLe, DateTime maintenant) {
    // Tout premier envoi, pas encore horodaté par le serveur.
    if (majLe == null) return EtatSignal.actif;
    final age = maintenant.difference(majLe);
    if (age >= delaiExpire) return EtatSignal.expire;
    if (age >= delaiPerdu) return EtatSignal.perdu;
    return EtatSignal.actif;
  }
}

/// "à l'instant", "il y a 45 s", "il y a 3 min".
String ilYA(DateTime? instant, DateTime maintenant) {
  if (instant == null) return "à l'instant";
  final age = maintenant.difference(instant);
  if (age.inSeconds < 5) return "à l'instant";
  if (age.inMinutes < 1) return 'il y a ${age.inSeconds} s';
  if (age.inHours < 1) return 'il y a ${age.inMinutes} min';
  return 'il y a ${age.inHours} h';
}

/// Temps d'attente estimé avant l'arrivée du chauffeur au point de prise
/// en charge (ou à destination, une fois le client à bord).
///
/// Estimation simple, sans calcul d'itinéraire : distance à vol d'oiseau
/// x [DistanceUtils.coefficientDetour], à la vitesse moyenne d'une
/// moto-taxi en ville (la même que pour la durée affichée avec le prix).
class Approche {
  const Approche({required this.distanceKm, required this.minutes});

  static const vitesseMoyenneKmh = 22.0;

  /// En dessous de 100 m, le chauffeur est considéré comme arrivé.
  static const distanceArriveeKm = 0.1;

  final double distanceKm;
  final int minutes;

  bool get arrive => distanceKm < distanceArriveeKm;

  factory Approche.estimer({
    required double latChauffeur,
    required double lngChauffeur,
    required double latCible,
    required double lngCible,
  }) {
    final distance = DistanceUtils.distanceRouteEstimeeKm(
      latDepart: latChauffeur,
      lngDepart: lngChauffeur,
      latArrivee: latCible,
      lngArrivee: lngCible,
    );
    final minutes = (distance / vitesseMoyenneKmh * 60).ceil();
    return Approche(distanceKm: distance, minutes: minutes < 1 ? 1 : minutes);
  }
}
