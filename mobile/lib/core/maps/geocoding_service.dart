import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../firebase_options.dart';
import '../firebase/fonctions_cloud.dart';

/// Adresse choisie, avec ses coordonnées GPS.
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

/// Suggestion affichée pendant la saisie. Les suggestions Google n'ont
/// pas encore de coordonnées : elles sont demandées au choix
/// ([ServiceAdresses.resoudre]), ce qui ne facture que l'adresse retenue.
class PropositionAdresse {
  const PropositionAdresse({
    required this.principal,
    this.secondaire = '',
    this.placeId,
    this.coordonnees,
  });

  /// "Université Cheikh Anta Diop"
  final String principal;

  /// "Avenue Cheikh Anta Diop, Dakar, Sénégal"
  final String secondaire;
  final String? placeId;

  /// Déjà connues (Nominatim) ; `null` pour une suggestion Google.
  final AdresseSuggestion? coordonnees;

  String get libelle => secondaire.isEmpty ? principal : '$principal, $secondaire';
}

/// Recherche d'adresses : Google Places (via les Cloud Functions, la clé
/// reste sur le serveur) en Firebase réel, Nominatim (OpenStreetMap) en
/// mode démo ou en secours.
abstract class ServiceAdresses {
  factory ServiceAdresses.parDefaut() =>
      DefaultFirebaseOptions.estConfigure ? AdressesGoogle(secours: GeocodingService()) : GeocodingService();

  Future<List<PropositionAdresse>> rechercher(String texte);

  /// Coordonnées de la suggestion choisie ; lève une exception si elles
  /// sont introuvables.
  Future<AdresseSuggestion> resoudre(PropositionAdresse proposition);
}

typedef AppelFonction = Future<Map<String, dynamic>> Function(String nom, Map<String, dynamic> donnees);

/// Google Places via les Cloud Functions `rechercherAdresses` et
/// `coordonneesAdresse`. Si le serveur ne répond pas (quota, panne), la
/// recherche bascule sur [secours] pour ne jamais bloquer une commande.
class AdressesGoogle implements ServiceAdresses {
  AdressesGoogle({required this.secours, AppelFonction? appeler}) : _appeler = appeler ?? FonctionsCloud.appeler;

  final ServiceAdresses secours;
  final AppelFonction _appeler;

  /// Jeton de la session en cours (exposé pour les tests).
  @visibleForTesting
  String get session => _session;

  /// Jeton de session Places : une saisie et son choix final sont
  /// facturés comme une seule session. Renouvelé après chaque choix.
  String _session = _nouvelleSession();

  static String _nouvelleSession() {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final aleatoire = Random.secure();
    return List.generate(32, (_) => alphabet[aleatoire.nextInt(alphabet.length)]).join();
  }

  @override
  Future<List<PropositionAdresse>> rechercher(String texte) async {
    final requete = texte.trim();
    if (requete.length < 3) return [];
    try {
      final reponse = await _appeler('rechercherAdresses', {'texte': requete, 'session': _session});
      return [
        for (final p in (reponse['propositions'] as List? ?? const []))
          if (p is Map)
            PropositionAdresse(
              principal: p['principal'] as String? ?? '',
              secondaire: p['secondaire'] as String? ?? '',
              placeId: p['placeId'] as String?,
            ),
      ];
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Recherche Google indisponible (${e.code}) : secours OpenStreetMap.');
      return secours.rechercher(requete);
    }
  }

  @override
  Future<AdresseSuggestion> resoudre(PropositionAdresse proposition) async {
    final connues = proposition.coordonnees;
    if (connues != null) return connues;
    try {
      final reponse = await _appeler('coordonneesAdresse', {
        'placeId': proposition.placeId,
        'session': _session,
      });
      return AdresseSuggestion(
        libelle: proposition.libelle,
        latitude: (reponse['latitude'] as num).toDouble(),
        longitude: (reponse['longitude'] as num).toDouble(),
      );
    } on FirebaseFunctionsException catch (e) {
      throw FonctionsCloud.versApiException(e);
    } finally {
      _session = _nouvelleSession();
    }
  }
}

/// Géocodage d'adresses via l'API publique Nominatim (OpenStreetMap) —
/// aucune clé API requise. Mode démo, et secours de [AdressesGoogle]. Instance Dio dédiée, sans intercepteur
/// d'authentification (ne doit jamais recevoir notre JWT, contrairement à
/// [ApiClient] qui cible notre propre backend).
///
/// La politique d'usage de Nominatim limite le débit à ~1 requête/s et
/// impose un User-Agent identifiable (voir [AddressSearchField] pour le
/// debounce). Pour un usage en production à plus grande échelle, prévoir
/// un Nominatim auto-hébergé ou un fournisseur payant (Google, Mapbox…).
class GeocodingService implements ServiceAdresses {
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

  @override
  Future<List<PropositionAdresse>> rechercher(String requete) async {
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
        final libelle = item['display_name'] as String;
        return PropositionAdresse(
          principal: libelle,
          coordonnees: AdresseSuggestion(
            libelle: libelle,
            latitude: double.parse(item['lat'] as String),
            longitude: double.parse(item['lon'] as String),
          ),
        );
      }).toList();
    } on DioException {
      return [];
    }
  }

  @override
  Future<AdresseSuggestion> resoudre(PropositionAdresse proposition) async => proposition.coordonnees!;
}
