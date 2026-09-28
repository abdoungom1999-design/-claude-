import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import '../../../core/config/api_config.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/firebase/fonctions_cloud.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../firebase_options.dart';
import 'course_service.dart';

class EstimationPrix {
  EstimationPrix({
    required this.distanceKm,
    required this.dureeEstimeeMin,
    required this.multiplicateurTrafic,
    required this.prixFcfa,
    this.motifMajoration,
  });

  final double distanceKm;
  final int dureeEstimeeMin;
  final double multiplicateurTrafic;
  final int prixFcfa;

  /// "Heure de pointe", "Tarif de nuit"… ; `null` sans majoration ou si
  /// la source (API) ne le précise pas.
  final String? motifMajoration;

  factory EstimationPrix.depuisJson(Map<String, dynamic> json) {
    return EstimationPrix(
      distanceKm: (json['distanceKm'] as num).toDouble(),
      dureeEstimeeMin: (json['dureeEstimeeMin'] as num).toInt(),
      multiplicateurTrafic: (json['multiplicateurTrafic'] as num).toDouble(),
      prixFcfa: (json['prixFcfa'] as num).toInt(),
      motifMajoration: json['motifMajoration'] as String?,
    );
  }
}

/// Prix d'une course avant commande. En Firebase réel, calculé par le
/// serveur (Cloud Function `estimerPrix`) à partir des coordonnées du
/// trajet : c'est ce même calcul que la fonction `creerCourse` refait au
/// moment de commander. En mode démo, calcul local ([DemoData]).
class PricingRepository {
  PricingRepository({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  final Dio _dio;

  /// [distanceKm] sert au mode démo ; le serveur recalcule la distance
  /// depuis [trajet].
  Future<EstimationPrix> estimer({
    required String type,
    required double distanceKm,
    PointsCourse? trajet,
  }) async {
    if (DefaultFirebaseOptions.estConfigure && trajet != null) {
      try {
        return EstimationPrix.depuisJson(await FonctionsCloud.appeler('estimerPrix', {
          'type': type,
          ...trajet.versServeur(),
        }));
      } on FirebaseFunctionsException catch (e) {
        throw FonctionsCloud.versApiException(e);
      }
    }
    if (ApiConfig.modeDemo) {
      await Future.delayed(const Duration(milliseconds: 350));
      return DemoData.estimerPrix(type: type, distanceKm: distanceKm);
    }
    try {
      final reponse = await _dio.post(
        '/pricing/estimer',
        data: {'type': type, 'distanceKm': distanceKm},
      );
      return EstimationPrix.depuisJson(reponse.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }
}
