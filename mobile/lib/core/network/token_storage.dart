import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage sécurisé des tokens JWT (Keychain iOS / Keystore Android via
/// flutter_secure_storage).
class TokenStorage {
  factory TokenStorage() => _instance;
  TokenStorage._internal();
  static final TokenStorage _instance = TokenStorage._internal();

  static const _cleAccessToken = 'sprint_access_token';
  static const _cleRefreshToken = 'sprint_refresh_token';

  final _storage = const FlutterSecureStorage();

  Future<void> enregistrerTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _cleAccessToken, value: accessToken);
    await _storage.write(key: _cleRefreshToken, value: refreshToken);
  }

  Future<String?> getAccessToken() => _storage.read(key: _cleAccessToken);

  Future<String?> getRefreshToken() => _storage.read(key: _cleRefreshToken);

  Future<void> effacerTokens() async {
    await _storage.delete(key: _cleAccessToken);
    await _storage.delete(key: _cleRefreshToken);
  }
}
