import 'package:dio/dio.dart';
import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/token_storage.dart';

/// Gère l'inscription, la connexion et la déconnexion pour les comptes
/// Client et Conducteur, et persiste les tokens JWT reçus.
///
/// En [ApiConfig.modeDemo] (build web sans backend public configuré),
/// l'authentification est simulée localement : aucun appel réseau n'est
/// fait, un jeton factice est stocké pour laisser l'app naviguer
/// normalement. Redevient un vrai flux réseau dès qu'un backend est
/// renseigné au build (`--dart-define=API_BASE_URL=...`).
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
    if (ApiConfig.modeDemo) {
      await _authentifierEnModeDemo();
      return;
    }
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

  /// Simule un aller-retour réseau réussi (délai réaliste + jeton
  /// factice) sans contacter de backend. Les écrans qui chargent des
  /// données après connexion (ex : tableau de bord Admin/Conducteur)
  /// afficheront tout de même leur propre message d'erreur réseau — seule
  /// l'authentification elle-même est simulée ici.
  Future<void> _authentifierEnModeDemo() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await _tokenStorage.enregistrerTokens(
      accessToken: 'demo-access-token',
      refreshToken: 'demo-refresh-token',
    );
  }
}
