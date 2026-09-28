import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprint/core/maps/fond_carte.dart';

/// Dio dont chaque requête reçoit [reponse] (ou échoue si `null`).
Dio _dioFactice(List<RequestOptions> requetes, {Map<String, dynamic>? reponse}) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    requetes.add(options);
    if (reponse == null) {
      handler.reject(DioException(requestOptions: options, response: Response(requestOptions: options, statusCode: 403)));
    } else {
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: reponse));
    }
  }));
  return dio;
}

final _maintenant = DateTime.utc(2026, 9, 29, 12);
int _secondes(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

Future<void> _carte(WidgetTester tester, FondCarte fond) async {
  await tester.pumpWidget(MaterialApp(
    home: FlutterMap(
      options: const MapOptions(initialCenter: LatLng(14.69, -17.44), initialZoom: 13),
      children: [CoucheFondCarte(fond: fond), MentionsFondCarte(fond: fond)],
    ),
  ));
  await tester.pump();
}

void main() {
  test('session Google : carte routière en français pour le Sénégal, réutilisée puis renouvelée', () async {
    final requetes = <RequestOptions>[];
    var maintenant = _maintenant;
    final fond = FondCarte(
      cle: 'CLE-WEB',
      maintenant: () => maintenant,
      dio: _dioFactice(requetes, reponse: {
        'session': 'JETON',
        'expiry': '${_secondes(_maintenant.add(const Duration(days: 14)))}',
      }),
    );

    final session = await fond.session();
    expect(session!.jeton, 'JETON');
    expect(requetes.single.uri.toString(), 'https://tile.googleapis.com/v1/createSession?key=CLE-WEB');
    expect(requetes.single.data, {'mapType': 'roadmap', 'language': 'fr-FR', 'region': 'SN'});
    expect(fond.optionsGoogle(session), {'session': 'JETON', 'key': 'CLE-WEB'});

    await fond.session();
    expect(requetes, hasLength(1)); // réutilisée

    maintenant = _maintenant.add(const Duration(days: 14));
    await fond.session();
    expect(requetes, hasLength(2)); // renouvelée avant expiration
  });

  test('sans clé : aucun appel à Google', () async {
    final requetes = <RequestOptions>[];
    final fond = FondCarte(cle: '', dio: _dioFactice(requetes, reponse: {}));
    expect(await fond.session(), isNull);
    expect(requetes, isEmpty);
  });

  test('session refusée (clé, quota) : secours OpenStreetMap, sans réessayer à chaque carte', () async {
    final requetes = <RequestOptions>[];
    final fond = FondCarte(cle: 'CLE-WEB', dio: _dioFactice(requetes));
    expect(await fond.session(), isNull);
    expect(fond.secours.value, isTrue);
    expect(await fond.session(), isNull);
    expect(requetes, hasLength(1));
  });

  test('images Google en erreur à répétition : secours OpenStreetMap', () {
    final fond = FondCarte(cle: 'CLE-WEB', dio: _dioFactice([], reponse: {}));
    for (var i = 0; i < FondCarte.erreursToleres - 1; i++) {
      fond.signalerErreur();
    }
    expect(fond.secours.value, isFalse);
    fond.signalerErreur();
    expect(fond.secours.value, isTrue);
  });

  testWidgets('carte Google : images Google et mentions Google', (tester) async {
    final fond = FondCarte(
      cle: 'CLE-WEB',
      maintenant: () => _maintenant,
      dio: _dioFactice([], reponse: {'session': 'JETON', 'expiry': '${_secondes(_maintenant.add(const Duration(days: 14)))}'}),
    );
    // Dio répond hors de l'horloge simulée des tests d'interface.
    await tester.runAsync(fond.session);
    await _carte(tester, fond);

    final couche = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(couche.urlTemplate, FondCarte.urlGoogle);
    expect(couche.additionalOptions, {'session': 'JETON', 'key': 'CLE-WEB'});
    expect(find.textContaining('Données cartographiques'), findsOneWidget);

    // Hors navigateur, les images ne se chargent pas : après quelques
    // échecs, la carte bascule d'elle-même sur OpenStreetMap.
    for (var i = 0; i < 20 && !fond.secours.value; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(fond.secours.value, isTrue);
    await tester.pump();
    expect(tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate, FondCarte.urlOpenStreetMap);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
  });

  testWidgets('sans clé : OpenStreetMap et ses mentions', (tester) async {
    await _carte(tester, FondCarte(cle: '', dio: _dioFactice([], reponse: {})));
    expect(tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate, FondCarte.urlOpenStreetMap);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
  });
}
