import 'package:dio/dio.dart';
import '../../../core/config/api_config.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

class ProfilConducteur {
  ProfilConducteur({
    required this.id,
    required this.nom,
    required this.telephone,
    required this.vehiculeId,
    required this.statut,
    required this.estValide,
    this.plaqueImmatriculation,
  });

  final String id;
  final String nom;
  final String telephone;
  final String? vehiculeId;
  final String statut; // 'EN_LIGNE' | 'HORS_LIGNE'
  final bool estValide;
  final String? plaqueImmatriculation;

  factory ProfilConducteur.depuisJson(Map<String, dynamic> json) {
    return ProfilConducteur(
      id: json['id'] as String,
      nom: json['nom'] as String,
      telephone: json['telephone'] as String,
      vehiculeId: json['vehiculeId'] as String?,
      statut: json['statut'] as String,
      estValide: json['estValide'] as bool,
      plaqueImmatriculation: json['plaqueImmatriculation'] as String?,
    );
  }
}

/// Accès aux endpoints Conducteur : profil, statut en ligne/hors ligne et
/// mise à jour de position GPS (relayée côté serveur vers Redis).
class ConducteurRepository {
  ConducteurRepository({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  final Dio _dio;

  Future<ProfilConducteur> monProfil() async {
    if (ApiConfig.modeDemo) {
      await _delaiDemo();
      return DemoData.monProfil();
    }
    try {
      final reponse = await _dio.get('/conducteurs/me');
      return ProfilConducteur.depuisJson(reponse.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }

  Future<String> mettreAJourStatut(String statut) async {
    if (ApiConfig.modeDemo) {
      await _delaiDemo();
      return DemoData.mettreAJourStatutConducteur(statut);
    }
    try {
      final reponse = await _dio.patch(
        '/conducteurs/me/statut',
        data: {'statut': statut},
      );
      return (reponse.data as Map<String, dynamic>)['statut'] as String;
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }

  Future<void> mettreAJourPosition({
    required double latitude,
    required double longitude,
  }) async {
    if (ApiConfig.modeDemo) {
      // Pas de Redis à alimenter en mode démo : simple no-op silencieux.
      return;
    }
    try {
      await _dio.patch(
        '/conducteurs/me/position',
        data: {'latitude': latitude, 'longitude': longitude},
      );
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }

  Future<void> _delaiDemo() =>
      Future.delayed(const Duration(milliseconds: 400));
}
