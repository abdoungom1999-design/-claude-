import 'package:dio/dio.dart';

class AdresseSuggestion {
  AdresseSuggestion({
    required this.libelle,
    required this.latitude,
    required this.longitude,
  });

  final String libelle;
  final double latitude;
  final double longitude;
}

/// Géocodage d'adresses via l'API publique Nominatim (OpenStreetMap) —
/// aucune clé API requise. Instance Dio dédiée, sans intercepteur
/// d'authentification (ne doit jamais recevoir notre JWT, contrairement à
/// [ApiClient] qui cible notre propre backend).
///
/// La politique d'usage de Nominatim limite le débit à ~1 requête/s et
/// impose un User-Agent identifiable (voir [AddressSearchField] pour le
/// debounce). Pour un usage en production à plus grande échelle, prévoir
/// un Nominatim auto-hébergé ou un fournisseur payant (Google, Mapbox…).
class GeocodingService {
  GeocodingService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: 'https://nominatim.openstreetmap.org',
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: {
            'User-Agent':
                'SprintApp-Dakar/1.0 (+https://github.com/abdoungom1999-design/-claude-)',
          },
        ),
      );

  final Dio _dio;

  /// Emprise approximative de Dakar et environs (left,top,right,bottom),
  /// pour prioriser les résultats locaux.
  static const _viewbox = '-17.63,14.85,-17.10,14.60';

  Future<List<AdresseSuggestion>> rechercher(String requete) async {
    final texte = requete.trim();
    if (texte.length < 3) return [];

    try {
      final reponse = await _dio.get(
        '/search',
        queryParameters: {
          'q': texte,
          'format': 'json',
          'limit': 5,
          'countrycodes': 'sn',
          'viewbox': _viewbox,
          'bounded': 1,
        },
      );

      return (reponse.data as List).map((item) {
        return AdresseSuggestion(
          libelle: item['display_name'] as String,
          latitude: double.parse(item['lat'] as String),
          longitude: double.parse(item['lon'] as String),
        );
      }).toList();
    } on DioException {
      return [];
    }
  }
}
