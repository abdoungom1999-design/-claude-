import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/google_maps_config.dart';
import '../network/api_exception.dart';

/// Suggestion d'adresse retournée par l'autocomplétion Google Places.
class SuggestionAdresseGoogle {
  const SuggestionAdresseGoogle({
    required this.description,
    required this.placeId,
  });

  final String description;
  final String placeId;
}

/// Résultat d'un calcul d'itinéraire réel (réseau routier), via
/// l'API Google Directions : tracé complet (pour dessiner la
/// polyligne sur la carte), distance et durée réelles — à la
/// différence de [DistanceUtils], qui ne calcule qu'une estimation à
/// vol d'oiseau (Haversine).
class ResultatItineraire {
  const ResultatItineraire({
    required this.points,
    required this.distanceKm,
    required this.dureeMin,
  });

  final List<LatLng> points;
  final double distanceKm;
  final int dureeMin;
}

/// Accès à l'API Google Maps Platform (Places, Geocoding, Directions),
/// pour remplacer à terme [GeocodingService] (Nominatim/OSM, gratuit
/// mais moins précis et limité en débit) et [DistanceUtils] (distance
/// à vol d'oiseau) par des données routières réelles.
///
/// Reste inopérant tant que [GoogleMapsConfig.estConfigure] est faux
/// (aucune clé fournie) : chaque méthode lève alors une [ApiException]
/// explicite plutôt que d'appeler Google avec une clé invalide. Voir
/// `GOOGLE_MAPS_SETUP.md` pour obtenir une clé.
///
/// Pour la position GPS de l'appareil lui-même (pas les adresses),
/// voir [DeviceLocationService] — ce service ne la duplique pas.
class MapService {
  MapService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: 'https://maps.googleapis.com/maps/api',
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

  final Dio _dio;

  void _verifierConfiguration() {
    if (!GoogleMapsConfig.estConfigure) {
      throw ApiException(
        "La clé API Google Maps n'est pas configurée (voir GOOGLE_MAPS_SETUP.md).",
      );
    }
  }

  /// Autocomplétion d'adresse (Places API), limitée au Sénégal.
  Future<List<SuggestionAdresseGoogle>> rechercherAdresses(String requete) async {
    _verifierConfiguration();
    final texte = requete.trim();
    if (texte.length < 3) return [];

    try {
      final reponse = await _dio.get(
        '/place/autocomplete/json',
        queryParameters: {
          'input': texte,
          'key': GoogleMapsConfig.apiKey,
          'components': 'country:sn',
          'language': 'fr',
        },
      );

      final statut = reponse.data['status'] as String;
      if (statut != 'OK' && statut != 'ZERO_RESULTS') {
        throw ApiException(_messagePourStatut(statut));
      }

      return (reponse.data['predictions'] as List).map((item) {
        return SuggestionAdresseGoogle(
          description: item['description'] as String,
          placeId: item['place_id'] as String,
        );
      }).toList();
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }

  /// Coordonnées d'un lieu Google Places, à partir de son `placeId`
  /// (renvoyé par [rechercherAdresses]).
  Future<LatLng> coordonneesDuLieu(String placeId) async {
    _verifierConfiguration();
    try {
      final reponse = await _dio.get(
        '/place/details/json',
        queryParameters: {
          'place_id': placeId,
          'key': GoogleMapsConfig.apiKey,
          'fields': 'geometry',
        },
      );

      final statut = reponse.data['status'] as String;
      if (statut != 'OK') throw ApiException(_messagePourStatut(statut));

      final localisation = reponse.data['result']['geometry']['location'];
      return LatLng(
        (localisation['lat'] as num).toDouble(),
        (localisation['lng'] as num).toDouble(),
      );
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }

  /// Géocodage direct : adresse en texte libre -> coordonnées.
  Future<LatLng> geocoderAdresse(String adresse) async {
    _verifierConfiguration();
    try {
      final reponse = await _dio.get(
        '/geocode/json',
        queryParameters: {
          'address': adresse,
          'key': GoogleMapsConfig.apiKey,
          'components': 'country:SN',
          'language': 'fr',
        },
      );

      final statut = reponse.data['status'] as String;
      if (statut != 'OK') throw ApiException(_messagePourStatut(statut));

      final localisation = (reponse.data['results'] as List).first['geometry']['location'];
      return LatLng(
        (localisation['lat'] as num).toDouble(),
        (localisation['lng'] as num).toDouble(),
      );
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }

  /// Géocodage inverse : coordonnées -> adresse lisible (ex. pour
  /// afficher l'adresse de départ à partir de la position GPS actuelle
  /// du conducteur ou du client).
  Future<String> adresseDepuisPosition(LatLng position) async {
    _verifierConfiguration();
    try {
      final reponse = await _dio.get(
        '/geocode/json',
        queryParameters: {
          'latlng': '${position.latitude},${position.longitude}',
          'key': GoogleMapsConfig.apiKey,
          'language': 'fr',
        },
      );

      final statut = reponse.data['status'] as String;
      if (statut != 'OK') throw ApiException(_messagePourStatut(statut));

      return (reponse.data['results'] as List).first['formatted_address'] as String;
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }

  /// Calcule un itinéraire réel (réseau routier) entre deux points :
  /// tracé pour dessiner la polyligne, distance et durée réelles pour
  /// la tarification — en remplacement, à terme, de la distance à vol
  /// d'oiseau utilisée aujourd'hui ([DistanceUtils]).
  Future<ResultatItineraire> calculerItineraire({
    required LatLng depart,
    required LatLng arrivee,
  }) async {
    _verifierConfiguration();
    try {
      final reponse = await _dio.get(
        '/directions/json',
        queryParameters: {
          'origin': '${depart.latitude},${depart.longitude}',
          'destination': '${arrivee.latitude},${arrivee.longitude}',
          'key': GoogleMapsConfig.apiKey,
          'language': 'fr',
          'region': 'sn',
        },
      );

      final statut = reponse.data['status'] as String;
      if (statut != 'OK') throw ApiException(_messagePourStatut(statut));

      final route = (reponse.data['routes'] as List).first;
      final jambe = (route['legs'] as List).first;

      return ResultatItineraire(
        points: _decoderPolyline(route['overview_polyline']['points'] as String),
        distanceKm: (jambe['distance']['value'] as num) / 1000.0,
        dureeMin: ((jambe['duration']['value'] as num) / 60).round(),
      );
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }
  }

  String _messagePourStatut(String statut) {
    switch (statut) {
      case 'ZERO_RESULTS':
        return 'Aucun résultat trouvé pour cette adresse.';
      case 'OVER_QUERY_LIMIT':
        return 'Quota Google Maps dépassé. Réessayez plus tard.';
      case 'REQUEST_DENIED':
        return 'Clé API Google Maps refusée (vérifiez les restrictions configurées).';
      case 'INVALID_REQUEST':
        return 'Requête invalide.';
      default:
        return 'Une erreur est survenue (Google Maps).';
    }
  }

  /// Décode une polyligne encodée (algorithme standard Google) en une
  /// liste de points, pour tracer l'itinéraire sur la carte.
  List<LatLng> _decoderPolyline(String encodee) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encodee.length) {
      var resultat = 0;
      var decalage = 0;
      int octet;
      do {
        octet = encodee.codeUnitAt(index++) - 63;
        resultat |= (octet & 0x1f) << decalage;
        decalage += 5;
      } while (octet >= 0x20);
      lat += (resultat & 1) != 0 ? ~(resultat >> 1) : (resultat >> 1);

      resultat = 0;
      decalage = 0;
      do {
        octet = encodee.codeUnitAt(index++) - 63;
        resultat |= (octet & 0x1f) << decalage;
        decalage += 5;
      } while (octet >= 0x20);
      lng += (resultat & 1) != 0 ? ~(resultat >> 1) : (resultat >> 1);

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
