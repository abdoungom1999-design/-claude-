import 'package:latlong2/latlong.dart';
import '../../../core/firebase/fonctions_cloud.dart';
import '../../../core/maps/distance_utils.dart';
import '../../../core/maps/geocoding_service.dart' show AppelFonction;
import '../../../core/maps/trace_utils.dart';

/// Itinéraire d'un chauffeur vers son client, puis vers la destination.
class Itineraire {
  const Itineraire({required this.trace, required this.distanceM, this.estime = false});

  /// Estimation à vol d'oiseau, quand le calcul d'itinéraire n'a pas répondu :
  /// une ligne droite, sans route, avec la distance par la route estimée à la
  /// louche (voir [DistanceUtils.coefficientDetour]).
  factory Itineraire.estimation(LatLng depuis, LatLng vers) => Itineraire(
        trace: [depuis, vers],
        distanceM: DistanceUtils.distanceRouteEstimeeKm(
              latDepart: depuis.latitude,
              lngDepart: depuis.longitude,
              latArrivee: vers.latitude,
              lngArrivee: vers.longitude,
            ) *
            1000,
        estime: true,
      );

  /// Tracé à suivre, du chauffeur au point visé.
  final List<LatLng> trace;

  /// Distance par la route, en mètres.
  final double distanceM;

  /// Vrai pour une estimation à vol d'oiseau ([Itineraire.estimation]) : le
  /// tracé n'est pas une route.
  final bool estime;
}

/// Calcul de l'itinéraire d'un chauffeur ; remplaçable dans les tests.
abstract interface class ServiceItineraire {
  /// Itinéraire de [depuis] vers le point visé de la course [courseId] ([vers] :
  /// le client tant que la course est acceptée, la destination une fois le client
  /// à bord). Lève une exception si le serveur ne répond pas : l'appelant garde
  /// alors l'itinéraire qu'il avait, ou se contente d'une estimation.
  Future<Itineraire> calculer({required String courseId, required LatLng depuis, required LatLng vers});
}

/// Itinéraire calculé par le serveur (Cloud Function `itineraireCourse`, Google
/// Routes) : la clé Google reste sur le serveur, qui lit lui-même le point visé
/// dans la course et ne répond qu'au chauffeur qui l'a acceptée.
class ItineraireCloud implements ServiceItineraire {
  ItineraireCloud({AppelFonction? appeler}) : _appeler = appeler ?? FonctionsCloud.appeler;

  final AppelFonction _appeler;

  @override
  Future<Itineraire> calculer({required String courseId, required LatLng depuis, required LatLng vers}) async {
    final reponse = await _appeler('itineraireCourse', {
      'courseId': courseId,
      'depuis': {'latitude': depuis.latitude, 'longitude': depuis.longitude},
    });
    final distanceM = (reponse['distanceM'] as num).toDouble();
    final trace = reponse['trace'];
    if (trace is! String) throw const FormatException('Réponse d\'itinéraire invalide.');
    // Tracé vide : le chauffeur est arrivé, la ligne droite suffit.
    return Itineraire(trace: trace.isEmpty ? [depuis, vers] : TraceUtils.decoder(trace), distanceM: distanceM);
  }
}
