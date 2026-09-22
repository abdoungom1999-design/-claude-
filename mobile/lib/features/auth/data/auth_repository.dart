import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/token_storage.dart';

/// Gère l'inscription, la connexion et la déconnexion pour les comptes
/// Client et Conducteur, et persiste les tokens JWT reçus.
class AuthRepository {
  AuthRepository({Dio? dio}) : _dio = dio ?? ApiClient().dio;

  final Dio _dio;
  final _tokenStorage = TokenStorage();

  Future<void> inscrireClient({
    required String nom,
    required String telephone,
    required String motDePasse,
  }) {
    return _authentifier('/auth/client/register', {
      'nom': nom,
      'telephone': telephone,
      'motDePasse': motDePasse,
    });
  }

  Future<void> connecterClient({
    required String telephone,
    required String motDePasse,
  }) {
    return _authentifier('/auth/client/login', {
      'telephone': telephone,
      'motDePasse': motDePasse,
    });
  }

  Future<void> inscrireConducteur({
    required String nom,
    required String telephone,
    required String motDePasse,
    String? vehiculeId,
  }) {
    return _authentifier('/auth/conducteur/register', {
      'nom': nom,
      'telephone': telephone,
      'motDePasse': motDePasse,
      if (vehiculeId != null && vehiculeId.trim().isNotEmpty)
        'vehiculeId': vehiculeId.trim(),
    });
  }

  Future<void> connecterConducteur({
    required String telephone,
    required String motDePasse,
  }) {
    return _authentifier('/auth/conducteur/login', {
      'telephone': telephone,
      'motDePasse': motDePasse,
    });
  }

  Future<void> connecterAdmin({
    required String email,
    required String motDePasse,
  }) {
    return _authentifier('/auth/admin/login', {
      'email': email,
      'motDePasse': motDePasse,
    });
  }

  Future<void> deconnecter() async {
    try {
      await _dio.post('/auth/logout');
    } catch (_) {
      // La déconnexion locale doit réussir même si l'appel réseau échoue.
    } finally {
      await _tokenStorage.effacerTokens();
    }
  }

  Future<void> _authentifier(
    String chemin,
    Map<String, dynamic> donnees,
  ) async {
    try {
      final reponse = await _dio.post(chemin, data: donnees);
      await _tokenStorage.enregistrerTokens(
        accessToken: reponse.data['accessToken'] as String,
        refreshToken: reponse.data['refreshToken'] as String,
      );
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }
}
