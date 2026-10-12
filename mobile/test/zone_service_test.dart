import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/demo/demo_data.dart';
import 'package:sprint/core/maps/distance_utils.dart';
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

  group('Grille de prix selon le départ (Dakar ou province)', () {
    test('Thiès, Mbour et leurs environs = province ; Dakar, sa banlieue et le reste = Dakar', () {
      const province = {
        'Thiès (centre)': (14.7910, -16.9359),
        'Mont-Rolland': (14.8333, -16.9),
        'Pout': (14.77, -17.05),
        'Mbour (centre)': (14.4196, -16.9640),
        'Saly': (14.4472, -17.0),
        'Somone': (14.4906, -17.0561),
        'Nianing': (14.3458, -17.0),
      };
      const dakar = {
        'Dakar (Plateau)': (14.6928, -17.4467),
        'Pointe des Almadies': (14.7447, -17.5436),
        'Keur Massar': (14.7836, -17.3114),
        'Rufisque': (14.7167, -17.2733),
        'Diamniadio': (14.7189, -17.1833),
        'Sébikotane': (14.75, -17.13),
        'Lac Rose': (14.8386, -17.2297),
        'Popenguine (au-delà des 20 km de Mbour)': (14.55, -17.12),
        'Saint-Louis (hors zone : grille de Dakar par défaut)': (16.0179, -16.4896),
      };
      for (final MapEntry(key: nom, value: (latitude, longitude)) in province.entries) {
        expect(ZoneDeService.zoneTarifaire(latitude, longitude), ZoneTarifaire.province, reason: nom);
      }
      for (final MapEntry(key: nom, value: (latitude, longitude)) in dakar.entries) {
        expect(ZoneDeService.zoneTarifaire(latitude, longitude), ZoneTarifaire.dakar, reason: nom);
      }
    });

    test('la limite exacte est le rayon (juste dedans = province, juste dehors = Dakar)', () {
      final thies = ZoneDeService.villesProvince.first;
      ZoneTarifaire auNord(double km) =>
          ZoneDeService.zoneTarifaire(thies.latitude + km / 111.195, thies.longitude);
      expect(auNord(thies.rayonKm - 0.1), ZoneTarifaire.province);
      expect(auNord(thies.rayonKm + 0.1), ZoneTarifaire.dakar);
    });

    test('les cercles de Thiès et de Mbour ne se touchent pas, et leurs centres sont dans la zone de service', () {
      final [thies, mbour] = ZoneDeService.villesProvince;
      final ecart = DistanceUtils.distanceKm(
        latDepart: thies.latitude,
        lngDepart: thies.longitude,
        latArrivee: mbour.latitude,
        lngArrivee: mbour.longitude,
      );
      expect(ecart, greaterThan(thies.rayonKm + mbour.rayonKm));
      for (final ville in ZoneDeService.villesProvince) {
        expect(_dedans(ville.latitude, ville.longitude), isTrue, reason: ville.nom);
      }
    });

    test('en attendant les prix de province du client : mêmes montants qu\'à Dakar, une seule grille pour la moto et le colis', () {
      // Quand le client donne les prix de Thiès et de Mbour, la première vérification est à mettre à jour avec eux.
      expect(
        DemoData.tarifs(ZoneTarifaire.province, 'PASSAGER'),
        DemoData.tarifs(ZoneTarifaire.dakar, 'PASSAGER'),
        reason: 'les prix de province ont été fixés : mettre ce test à jour',
      );
      // L'écran Admin « Règles en vigueur » n'affiche qu'une grille par zone : elle vaut pour la moto et le colis.
      for (final zone in ZoneTarifaire.values) {
        expect(DemoData.tarifs(zone, 'COLIS'), DemoData.tarifs(zone, 'PASSAGER'), reason: '$zone');
      }
    });

    test('le mode démo calcule le prix avec la grille de la zone demandée (Dakar par défaut)', () {
      final midi = DateTime.utc(2026, 10, 12, 12);
      final parDefaut = DemoData.estimerPrix(type: 'PASSAGER', distanceKm: 15, maintenant: midi);
      expect(parDefaut.prixFcfa, 3300);
      for (final zone in ZoneTarifaire.values) {
        expect(DemoData.estimerPrix(type: 'PASSAGER', distanceKm: 15, maintenant: midi, zone: zone).prixFcfa, 3300);
      }
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
