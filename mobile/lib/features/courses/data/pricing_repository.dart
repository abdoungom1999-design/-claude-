import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

class EstimationPrix {
  EstimationPrix({
    required this.distanceKm,
    required this.dureeEstimeeMin,
    required this.multiplicateurTrafic,
    required this.prixFcfa,
  });

  final double distanceKm;
  final int dureeEstimeeMin;
  final double multiplicateurTrafic;
  final int prixFcfa;

  factory EstimationPrix.depuisJson(Map<String, dynamic> json) {
    return EstimationPrix(
      distanceKm: (json['distanceKm'] as num).toDouble(),
      dureeEstimeeMin: json['dureeEstimeeMin'] as int,
      multiplicateurTrafic: (json['multiplicateurTrafic'] as num).toDouble(),
      prixFcfa: json['prixFcfa'] as int,
    );
  }
}

/// Prévisualisation du prix d'une course avant commande (algorithme
/// distance + temps + multiplicateur de trafic, calculé côté serveur).
class PricingRepository {
  PricingRepository({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  final Dio _dio;

  Future<EstimationPrix> estimer({
    required String type,
    required double distanceKm,
  }) async {
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
