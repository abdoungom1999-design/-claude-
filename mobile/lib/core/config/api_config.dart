import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// URL de base de l'API Sprint (NestJS).
///
/// Peut être fixée à la compilation avec `--dart-define=API_BASE_URL=...`
/// (utilisé par le build web pour cibler un backend accessible
/// publiquement). Sans cette valeur, on retombe sur les adresses de
/// développement local : l'émulateur Android accède à la machine hôte via
/// `10.0.2.2` (et non `localhost`) ; iOS Simulator, desktop et web
/// utilisent directement `localhost`. Un appareil physique nécessite
/// l'adresse IP locale de la machine qui héberge l'API.
class ApiConfig {
  ApiConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) {
      return _override;
    }
    if (kIsWeb) {
      return 'http://localhost:3000';
    }
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }
}
