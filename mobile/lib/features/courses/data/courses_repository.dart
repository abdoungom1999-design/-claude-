import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

/// Création d'une course (Passager ou Colis) auprès de l'API.
class CoursesRepository {
  CoursesRepository({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  final Dio _dio;

  Future<void> creerCourse(Map<String, dynamic> donnees) async {
    try {
      await _dio.post('/courses', data: donnees);
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }
}
