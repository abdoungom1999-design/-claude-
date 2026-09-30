import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprint/core/maps/fond_carte.dart';
import 'package:sprint/core/maps/style_sprint_clair.dart';

/// Dio dont chaque requête reçoit [reponse] (ou échoue si `null`, avec
/// le code [codeErreur]). [refuserStyle] : une demande avec style est
/// refusée (400), comme le ferait Google pour un style invalide.
Dio _dioFactice(
  List<RequestOptions> requetes, {
  Map<String, dynamic>? reponse,
  int codeErreur = 403,
  bool refuserStyle = false,
}) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    requetes.add(options);
    final avecStyle = (options.data as Map?)?.containsKey('styles') ?? false;
    if (reponse == null || (refuserStyle && avecStyle)) {
      final code = refuserStyle && avecStyle ? 400 : codeErreur;
      handler.reject(DioException(requestOptions: options, response: Response(requestOptions: options, statusCode: code)));
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
  test('session Google : carte routière en français pour le Sénégal, style Sprint clair, réutilisée puis renouvelée', () async {
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
    expect(requetes.single.data, {'mapType': 'roadmap', 'language': 'fr-FR', 'region': 'SN', 'styles': styleSprintClair});
    expect(fond.optionsGoogle(session), {'session': 'JETON', 'key': 'CLE-WEB'});

    await fond.session();
    expect(requetes, hasLength(1)); // réutilisée

    maintenant = _maintenant.add(const Duration(days: 14));
    await fond.session();
    expect(requetes, hasLength(2)); // renouvelée avant expiration
  });

  test('APK Android : identité de l\'app (package + SHA-1) jointe à la demande de session', () async {
    final requetes = <RequestOptions>[];
    final fond = FondCarte(
      cle: 'CLE-ANDROID',
      entetes: FondCarte.entetesAndroid,
      maintenant: () => _maintenant,
      dio: _dioFactice(requetes, reponse: {
        'session': 'JETON',
        'expiry': '${_secondes(_maintenant.add(const Duration(days: 14)))}',
      }),
    );
    await fond.session();
    expect(requetes.single.headers['X-Android-Package'], 'sn.groupesantine.sprint');
    expect(requetes.single.headers['X-Android-Cert'], matches(RegExp(r'^[0-9A-F]{40}$')));
  });

  testWidgets('APK Android : identité de l\'app jointe aussi aux images de la carte', (tester) async {
    final fond = FondCarte(
      cle: 'CLE-ANDROID',
      entetes: FondCarte.entetesAndroid,
      maintenant: () => _maintenant,
      dio: _dioFactice([], reponse: {'session': 'JETON', 'expiry': '${_secondes(_maintenant.add(const Duration(days: 14)))}'}),
    );
    await tester.runAsync(fond.session);
    await _carte(tester, fond);
    final fournisseur = tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider as NetworkTileProvider;
    expect(fournisseur.headers, containsPair('X-Android-Package', 'sn.groupesantine.sprint'));
    expect(fournisseur.headers, containsPair('X-Android-Cert', FondCarte.entetesAndroid['X-Android-Cert']));
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

  test('style refusé par Google (400) : carte Google sans style, pas OpenStreetMap', () async {
    final requetes = <RequestOptions>[];
    final fond = FondCarte(
      cle: 'CLE-WEB',
      maintenant: () => _maintenant,
      dio: _dioFactice(
        requetes,
        refuserStyle: true,
        reponse: {'session': 'SANS-STYLE', 'expiry': '${_secondes(_maintenant.add(const Duration(days: 14)))}'},
      ),
    );
    expect((await fond.session())!.jeton, 'SANS-STYLE');
    expect(fond.secours.value, isFalse);
    expect(requetes, hasLength(2));
    expect((requetes.last.data as Map).containsKey('styles'), isFalse);
  });

  test('style : aucune règle vide, couleurs au format #rrggbb', () {
    for (final regle in styleSprintClair) {
      final stylers = regle['stylers']! as List;
      expect(stylers, isNotEmpty);
      for (final s in stylers.cast<Map<String, Object>>()) {
        final couleur = s['color'];
        if (couleur != null) expect(couleur, matches(RegExp(r'^#[0-9a-f]{6}$')));
      }
    }
  });

  test('style Silver : uniquement des gris (ni vert, ni jaune, ni bleu franc)', () {
    for (final regle in styleSprintClair) {
      for (final s in (regle['stylers']! as List).cast<Map<String, Object>>()) {
        final couleur = s['color'] as String?;
        if (couleur == null) continue;
        final canaux = [for (var i = 1; i < 7; i += 2) int.parse(couleur.substring(i, i + 2), radix: 16)];
        final ecart = canaux.reduce((a, b) => a > b ? a : b) - canaux.reduce((a, b) => a < b ? a : b);
        expect(ecart, lessThanOrEqualTo(20), reason: '$couleur est trop colorée pour un style Silver');
      }
    }
  });

  test('images OpenStreetMap : le filtre les passe en gris (vert et jaune disparaissent)', () {
    // Un vert de parc OSM (#cdebb0) et un jaune de route (#f7fabf) : après le
    // filtre, les trois canaux doivent être proches.
    double sortie(List<double> ligne, List<int> rgb) =>
        ligne[0] * rgb[0] + ligne[1] * rgb[1] + ligne[2] * rgb[2] + ligne[4];
    const m = <List<double>>[
      [0.20, 0.62, 0.065, 0, 24],
      [0.19, 0.63, 0.065, 0, 24],
      [0.19, 0.62, 0.075, 0, 24],
    ];
    for (final rgb in [
      [0xcd, 0xeb, 0xb0],
      [0xf7, 0xfa, 0xbf],
    ]) {
      final valeurs = [for (final l in m) sortie(l, rgb)];
      final ecart = valeurs.reduce((a, b) => a > b ? a : b) - valeurs.reduce((a, b) => a < b ? a : b);
      expect(ecart, lessThan(12));
    }
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
