import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// URL de base de l'API Sprint (NestJS).
///
/// En développement, l'émulateur Android accède à la machine hôte via
/// `10.0.2.2` (et non `localhost`) ; iOS Simulator, desktop et web
/// utilisent directement `localhost`. Un appareil physique nécessite
/// l'adresse IP locale de la machine qui héberge l'API.
class ApiConfig {
  ApiConfig._();

  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:3000';
    }
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }
}
