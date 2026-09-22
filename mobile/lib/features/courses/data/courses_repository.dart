import 'package:dio/dio.dart';
import '../../../core/config/api_config.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

class CourseCreee {
  CourseCreee({required this.id, this.prixFcfa, this.dureeEstimeeMin});

  final String id;
  final int? prixFcfa;
  final int? dureeEstimeeMin;

  factory CourseCreee.depuisJson(Map<String, dynamic> json) {
    return CourseCreee(
      id: json['id'] as String,
      prixFcfa: json['prixFcfa'] as int?,
      dureeEstimeeMin: json['dureeEstimeeMin'] as int?,
    );
  }
}

/// Création d'une course (Passager ou Colis) auprès de l'API. Le prix
/// retourné est toujours celui calculé côté serveur (voir PricingService),
/// jamais une valeur envoyée par le client.
class CoursesRepository {
  CoursesRepository({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  final Dio _dio;

  Future<CourseCreee> creerCourse(Map<String, dynamic> donnees) async {
    if (ApiConfig.modeDemo) {
      await Future.delayed(const Duration(milliseconds: 600));
      final estimation = DemoData.estimerPrix(
        type: donnees['type'] as String? ?? 'PASSAGER',
        distanceKm: (donnees['distanceKm'] as num?)?.toDouble() ?? 0,
      );
      return CourseCreee(
        id: DemoData.nouvelIdCourse(),
        prixFcfa: estimation.prixFcfa,
        dureeEstimeeMin: estimation.dureeEstimeeMin,
      );
    }
    try {
      final reponse = await _dio.post('/courses', data: donnees);
      return CourseCreee.depuisJson(reponse.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }
}
