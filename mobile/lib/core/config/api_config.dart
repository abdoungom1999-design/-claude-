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

  /// Mode démo : l'app (web ou APK Android) tourne sans l'ancienne API
  /// REST (aucun `--dart-define=API_BASE_URL` fourni). Les rares appels
  /// qui passaient encore par elle (profil et statut du chauffeur) sont
  /// alors traités localement plutôt que d'échouer sur chaque appel
  /// réseau ; tout le reste passe par Firebase. Se désactive
  /// automatiquement dès qu'un vrai backend est renseigné au build —
  /// aucun interrupteur séparé à retourner. Hors web et Android (tests,
  /// poste de développement), l'API locale reste utilisée.
  static bool get modeDemo => (kIsWeb || Platform.isAndroid) && _override.isEmpty;
}
