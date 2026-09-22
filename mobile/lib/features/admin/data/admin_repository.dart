import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

class ConducteurAdmin {
  ConducteurAdmin({
    required this.id,
    required this.nom,
    required this.telephone,
    required this.vehiculeId,
    required this.statut,
    required this.estValide,
  });

  final String id;
  final String nom;
  final String telephone;
  final String? vehiculeId;
  final String statut;
  final bool estValide;

  factory ConducteurAdmin.depuisJson(Map<String, dynamic> json) {
    return ConducteurAdmin(
      id: json['id'] as String,
      nom: json['nom'] as String,
      telephone: json['telephone'] as String,
      vehiculeId: json['vehiculeId'] as String?,
      statut: json['statut'] as String,
      estValide: json['estValide'] as bool,
    );
  }
}

/// Accès aux endpoints Admin : liste des conducteurs, validation et rejet
/// des comptes en attente.
class AdminRepository {
  AdminRepository({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  final Dio _dio;

  Future<List<ConducteurAdmin>> listerConducteurs() async {
    try {
      final reponse = await _dio.get('/admin/conducteurs');
      return (reponse.data as List)
          .map((json) => ConducteurAdmin.depuisJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }

  Future<void> validerConducteur(String id) async {
    try {
      await _dio.patch('/admin/conducteurs/$id/valider');
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }

  Future<void> rejeterConducteur(String id) async {
    try {
      await _dio.delete('/admin/conducteurs/$id');
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }
}
