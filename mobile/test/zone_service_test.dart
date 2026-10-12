import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/maps/geocoding_service.dart';
import 'package:sprint/core/maps/zone_service.dart';

/// Nominatim simulé : garde la dernière requête reçue et répond avec [corps].
class _NominatimFactice implements HttpClientAdapter {
  _NominatimFactice(this.corps);

  final List<Map<String, dynamic>> corps;
  final requetes = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requetes.add(options);
    return ResponseBody.fromString(
      jsonEncode(corps),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

bool _dedans(double latitude, double longitude) =>
    latitude >= ZoneDeService.sud &&
    latitude <= ZoneDeService.nord &&
    longitude >= ZoneDeService.ouest &&
    longitude <= ZoneDeService.est;

void main() {
  group('Zone de service (Dakar, Thiès, Mbour)', () {
    test('Dakar, Thiès, Mbour et les routes qui les relient sont dedans', () {
      const lieux = {
        'Dakar (Plateau)': (14.6928, -17.4467),
        'Pointe des Almadies': (14.7447, -17.5436),
        'Keur Massar': (14.7836, -17.3114),
        'Rufisque': (14.7167, -17.2733),
        'Diamniadio': (14.7189, -17.1833),
        'Thiès': (14.7910, -16.9359),
        'Mbour': (14.4196, -16.9640),
        'Saly': (14.4472, -17.0),
        'Nianing': (14.3458, -17.0),
      };
      for (final MapEntry(key: nom, value: (latitude, longitude)) in lieux.entries) {
        expect(_dedans(latitude, longitude), isTrue, reason: '$nom doit être dans la zone');
      }
    });

    test("les autres villes restent dehors tant qu'on ne les ajoute pas", () {
      const lieux = {
        'Saint-Louis': (16.0179, -16.4896),
        'Louga': (15.6144, -16.2246),
        'Touba': (14.85, -15.8833),
        'Kaolack': (14.1652, -16.0758),
        'Joal-Fadiouth': (14.1667, -16.8333),
        'Ziguinchor': (12.5833, -16.2719),
        'Banjul (Gambie)': (13.4549, -16.579),
      };
      for (final MapEntry(key: nom, value: (latitude, longitude)) in lieux.entries) {
        expect(_dedans(latitude, longitude), isFalse, reason: '$nom doit rester hors de la zone');
      }
    });

    test("élargir ne retire rien à Dakar : l'ancien rectangle de Dakar est entièrement dedans", () {
      expect(ZoneDeService.ouest, lessThanOrEqualTo(-17.63));
      expect(ZoneDeService.est, greaterThanOrEqualTo(-17.10));
      expect(ZoneDeService.nord, greaterThanOrEqualTo(14.85));
      expect(ZoneDeService.sud, lessThanOrEqualTo(14.60));
    });

    test('le rectangle Nominatim est écrit gauche, haut, droite, bas, avec les mêmes bords', () {
      final bords = ZoneDeService.viewbox.split(',').map(double.parse).toList();
      expect(bords, [ZoneDeService.ouest, ZoneDeService.nord, ZoneDeService.est, ZoneDeService.sud]);
      // gauche < droite et bas < haut : sinon Nominatim ne trouverait rien.
      expect(bords[0], lessThan(bords[2]));
      expect(bords[3], lessThan(bords[1]));
    });
  });

  group('Recherche d\'adresses de secours (Nominatim)', () {
    test('cherche dans la zone de service, au Sénégal, et rend une adresse de Thiès', () async {
      final nominatim = _NominatimFactice([
        {'display_name': 'Avenue Caporal Mamadou Ndiaye, Thiès, Sénégal', 'lat': '14.7915', 'lon': '-16.9265'},
      ]);
      final service = GeocodingService(dio: Dio()..httpClientAdapter = nominatim);

      final propositions = await service.rechercher('Avenue Caporal Mamadou Ndiaye');

      expect(nominatim.requetes, hasLength(1));
      final parametres = nominatim.requetes.single.queryParameters;
      expect(parametres['viewbox'], ZoneDeService.viewbox);
      expect(parametres['bounded'], 1, reason: 'la recherche reste limitée au rectangle');
      expect(parametres['countrycodes'], 'sn');
      expect(propositions, hasLength(1));
      final adresse = propositions.single.coordonnees!;
      expect(adresse.latitude, 14.7915);
      expect(adresse.longitude, -16.9265);
      expect(_dedans(adresse.latitude, adresse.longitude), isTrue);
    });

    test('moins de 3 lettres : aucune requête (comme avant)', () async {
      final nominatim = _NominatimFactice(const []);
      final service = GeocodingService(dio: Dio()..httpClientAdapter = nominatim);

      expect(await service.rechercher(' ab '), isEmpty);
      expect(nominatim.requetes, isEmpty);
    });
  });
}
