import 'package:dio/dio.dart';
import '../../../core/config/api_config.dart';
import '../../../core/demo/demo_data.dart';
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
    this.note = 0.0,
    this.suspendu = false,
  });

  final String id;
  final String nom;
  final String telephone;
  final String? vehiculeId;
  final String statut;
  final bool estValide;

  /// Note moyenne donnée par les clients (sur 5).
  final double note;

  /// Bloqué par un administrateur (Tour de Contrôle) : distinct de
  /// [estValide], qui ne concerne que la validation initiale des
  /// documents.
  final bool suspendu;

  factory ConducteurAdmin.depuisJson(Map<String, dynamic> json) {
    return ConducteurAdmin(
      id: json['id'] as String,
      nom: json['nom'] as String,
      telephone: json['telephone'] as String,
      vehiculeId: json['vehiculeId'] as String?,
      statut: json['statut'] as String,
      estValide: json['estValide'] as bool,
      note: (json['note'] as num?)?.toDouble() ?? 0.0,
      suspendu: json['suspendu'] as bool? ?? false,
    );
  }
}

/// Accès aux endpoints Admin : liste des conducteurs, validation et rejet
/// des comptes en attente.
class AdminRepository {
  AdminRepository({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  final Dio _dio;

  Future<List<ConducteurAdmin>> listerConducteurs() async {
    if (ApiConfig.modeDemo) {
      await _delaiDemo();
      return DemoData.listerConducteurs();
    }
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
    if (ApiConfig.modeDemo) {
      await _delaiDemo();
      DemoData.validerConducteur(id);
      return;
    }
    try {
      await _dio.patch('/admin/conducteurs/$id/valider');
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }

  Future<void> rejeterConducteur(String id) async {
    if (ApiConfig.modeDemo) {
      await _delaiDemo();
      DemoData.rejeterConducteur(id);
      return;
    }
    try {
      await _dio.delete('/admin/conducteurs/$id');
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }

  Future<void> bloquerConducteur(String id) async {
    if (ApiConfig.modeDemo) {
      await _delaiDemo();
      DemoData.bloquerConducteur(id);
      return;
    }
    try {
      await _dio.patch('/admin/conducteurs/$id/bloquer');
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }

  Future<void> debloquerConducteur(String id) async {
    if (ApiConfig.modeDemo) {
      await _delaiDemo();
      DemoData.debloquerConducteur(id);
      return;
    }
    try {
      await _dio.patch('/admin/conducteurs/$id/debloquer');
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }

  Future<void> _delaiDemo() =>
      Future.delayed(const Duration(milliseconds: 400));
}
