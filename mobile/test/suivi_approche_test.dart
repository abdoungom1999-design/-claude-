import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/widgets/moto_vue_dessus.dart';
import 'package:sprint/features/client/presentation/widgets/suivi_approche.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/position_chauffeur.dart';

// Point de prise en charge : Place de l'Indépendance ; destination : Almadies.
const _points = PointsCourse(
  latitudeDepart: 14.6680,
  longitudeDepart: -17.4380,
  latitudeArrivee: 14.7450,
  longitudeArrivee: -17.5170,
);

CourseFirestore _course(String statut, {PointsCourse? points = _points}) => CourseFirestore(
      id: 'c1',
      clientId: 'client',
      chauffeurId: 'moussa',
      statut: statut,
      type: 'PASSAGER',
      adresseDepart: 'Plateau',
      adresseArrivee: 'Almadies',
      prixFcfa: 3000,
      methodePaiement: 'WAVE',
      timestamp: DateTime(2026, 9, 27),
      points: points,
    );

PositionChauffeurDirect _position(double lat, double lng, {Duration age = Duration.zero}) =>
    PositionChauffeurDirect(uid: 'moussa', latitude: lat, longitude: lng, majLe: DateTime.now().subtract(age));

const _marqueur = Key('marqueur-chauffeur');

Future<StreamController<PositionChauffeurDirect?>> _afficher(WidgetTester tester, CourseFirestore course) async {
  final flux = StreamController<PositionChauffeurDirect?>();
  addTearDown(flux.close);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SuiviApproche(course: course, positions: flux.stream, coucheFond: const SizedBox.shrink())),
  ));
  return flux;
}

void main() {
  group('Temps d\'approche', () {
    test('~1,2 km par la route à 22 km/h : 4 min (arrondi au-dessus)', () {
      // 0,0098° de latitude ≈ 1,09 km à vol d'oiseau, x1,1 ≈ 1,2 km.
      final approche = Approche.estimer(latChauffeur: 14.6778, lngChauffeur: -17.4380, latCible: 14.6680, lngCible: -17.4380);
      expect(approche.distanceKm, closeTo(1.2, 0.02));
      expect(approche.minutes, 4);
      expect(approche.arrive, isFalse);
    });

    test('à moins de 100 m : arrivé ; jamais moins d\'1 min', () {
      final approche = Approche.estimer(latChauffeur: 14.6684, lngChauffeur: -17.4380, latCible: 14.6680, lngCible: -17.4380);
      expect(approche.arrive, isTrue);
      expect(approche.minutes, 1);
    });

    test('course sans coordonnées enregistrées : pas de points', () {
      expect(PointsCourse.depuisDocument({'adresseDepart': 'Plateau'}), isNull);
      expect(PointsCourse.depuisDocument(_points.versDocument())?.longitudeArrivee, -17.5170);
    });
  });

  group('Carte de suivi côté client', () {
    testWidgets('attente, approche, puis chauffeur arrivé', (tester) async {
      final flux = await _afficher(tester, _course(StatutCourse.acceptee));
      await tester.pump();
      expect(find.text('Localisation du chauffeur…'), findsOneWidget);
      expect(find.byKey(_marqueur), findsNothing); // pas encore de chauffeur sur la carte
      expect(find.text('En direct'), findsNothing);

      flux.add(_position(14.6778, -17.4380));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('Votre chauffeur arrive dans ~4 min'), findsOneWidget);
      expect(find.text('À 1,2 km de vous'), findsOneWidget);
      // Marqueur du chauffeur sur la carte, en plus de celui du point de départ.
      expect(find.byKey(_marqueur), findsOneWidget);
      expect(find.byType(MotoVueDessus), findsOneWidget);
      expect(find.byIcon(Icons.person_pin_circle_rounded), findsOneWidget);
      expect(find.text('En direct'), findsOneWidget);

      flux.add(_position(14.6684, -17.4380));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('Votre chauffeur est arrivé'), findsOneWidget);
    });

    testWidgets("l'icône glisse d'une position à l'autre au lieu de sauter", (tester) async {
      final flux = await _afficher(tester, _course(StatutCourse.acceptee));
      await tester.pump();
      flux.add(_position(14.6778, -17.4380));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));
      final avant = tester.getCenter(find.byKey(_marqueur));

      flux.add(_position(14.6740, -17.4380));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final pendant = tester.getCenter(find.byKey(_marqueur));
      await tester.pump(const Duration(milliseconds: 700));
      final apres = tester.getCenter(find.byKey(_marqueur));

      // Le cadrage suit le chauffeur : on compare les positions relatives
      // en s'assurant simplement que l'icône a bougé en plusieurs étapes.
      expect(pendant, isNot(equals(avant)));
      expect(apres, isNot(equals(pendant)));
    });

    testWidgets('client à bord : temps restant jusqu\'à destination', (tester) async {
      final flux = await _afficher(tester, _course(StatutCourse.enCours));
      await tester.pump();
      flux.add(_position(14.7000, -17.4700));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.textContaining('Arrivée dans ~'), findsOneWidget);
      expect(find.textContaining("jusqu'à destination"), findsOneWidget);
      expect(find.byIcon(Icons.location_on_rounded), findsOneWidget);
    });

    testWidgets('signal perdu depuis 5 min : pas de fausse estimation', (tester) async {
      final flux = await _afficher(tester, _course(StatutCourse.acceptee));
      await tester.pump();
      flux.add(_position(14.6778, -17.4380, age: const Duration(minutes: 5)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('Position non mise à jour'), findsOneWidget);
      expect(find.textContaining('arrive dans'), findsNothing);
    });

    testWidgets('lecture refusée : message clair, sans bloquer l\'écran', (tester) async {
      final flux = await _afficher(tester, _course(StatutCourse.acceptee));
      await tester.pump();
      flux.addError(Exception('permission-denied'));
      await tester.pump();
      expect(find.text('Suivi indisponible'), findsOneWidget);
    });

    testWidgets('ancienne course sans coordonnées : chauffeur visible, sans estimation', (tester) async {
      final flux = await _afficher(tester, _course(StatutCourse.acceptee, points: null));
      await tester.pump();
      flux.add(_position(14.6778, -17.4380));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('Votre chauffeur est en route'), findsOneWidget);
    });
  });

  group('Suivi en direct : position exacte, cap, caméra', () {
    // Dakar : 0,0009° de latitude ≈ 100 m.
    const lat0 = 14.6700;
    const lng0 = -17.4380;

    test('capEntre : nord, est, sud, ouest', () {
      expect(capEntre(lat0, lng0, lat0 + 0.001, lng0), closeTo(0, 0.5));
      expect(capEntre(lat0, lng0, lat0, lng0 + 0.001), closeTo(90, 0.5));
      expect(capEntre(lat0, lng0, lat0 - 0.001, lng0), closeTo(180, 0.5));
      expect(capEntre(lat0, lng0, lat0, lng0 - 0.001), closeTo(270, 0.5));
    });

    test('la position lue n\'est jamais arrondie : les décimales GPS arrivent intactes', () {
      final lue = PositionChauffeurDirect.depuisDocument('moussa', {
        'latitude': 14.693512345678,
        'longitude': -17.446698765432,
        'cap': 87.5,
        'vitesse': 6.2,
      })!;
      expect(lue.latitude, 14.693512345678);
      expect(lue.longitude, -17.446698765432);
      expect(lue.cap, 87.5);
      expect(lue.vitesse, 6.2);
    });

    test('cap ou vitesse absents ou NaN : null, pas d\'orientation inventée', () {
      final lue = PositionChauffeurDirect.depuisDocument('m', {
        'latitude': 14.69,
        'longitude': -17.44,
        'cap': double.nan,
      })!;
      expect(lue.cap, isNull);
      expect(lue.vitesse, isNull);
    });

    Future<({StreamController<PositionChauffeurDirect?> flux, MapController carte, List<DateTime> heure})> ouvrir(
      WidgetTester tester,
    ) async {
      final flux = StreamController<PositionChauffeurDirect?>();
      addTearDown(flux.close);
      final carte = MapController();
      final heure = [DateTime(2026, 9, 29, 12)];
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SuiviApproche(
            course: _course(StatutCourse.acceptee),
            positions: flux.stream,
            coucheFond: const SizedBox.shrink(),
            controleurCarte: carte,
            horloge: () => heure.first,
          ),
        ),
      ));
      await tester.pump();
      return (flux: flux, carte: carte, heure: heure);
    }

    PositionChauffeurDirect direct(double lat, double lng, DateTime heure) =>
        PositionChauffeurDirect(uid: 'moussa', latitude: lat, longitude: lng, majLe: heure);

    Future<void> avancer(WidgetTester tester, List<DateTime> heure, Duration duree) async {
      heure[0] = heure[0].add(duree);
      await tester.pump(duree);
    }

    testWidgets('la moto pointe dans le sens de la marche (vers le nord, puis vers l\'est)', (tester) async {
      final t = await ouvrir(tester);
      t.flux.add(direct(lat0, lng0, t.heure.first));
      await avancer(tester, t.heure, const Duration(seconds: 2));
      t.flux.add(direct(lat0 + 0.0009, lng0, t.heure.first)); // ~100 m au nord
      await avancer(tester, t.heure, const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<MotoVueDessus>(find.byType(MotoVueDessus)).cap, closeTo(0, 1));

      t.flux.add(direct(lat0 + 0.0009, lng0 + 0.0009, t.heure.first)); // ~100 m à l'est
      await avancer(tester, t.heure, const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<MotoVueDessus>(find.byType(MotoVueDessus)).cap, closeTo(90, 1));
    });

    testWidgets('à l\'arrêt (GPS qui bruite de 1 m) : la moto ne pivote pas au hasard', (tester) async {
      final t = await ouvrir(tester);
      t.flux.add(direct(lat0, lng0, t.heure.first));
      await avancer(tester, t.heure, const Duration(seconds: 2));
      t.flux.add(direct(lat0 + 0.0009, lng0, t.heure.first));
      await avancer(tester, t.heure, const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      final avant = tester.widget<MotoVueDessus>(find.byType(MotoVueDessus)).cap;

      t.flux.add(direct(lat0 + 0.0009, lng0 + 0.00001, t.heure.first)); // ~1 m à l'est
      await avancer(tester, t.heure, const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<MotoVueDessus>(find.byType(MotoVueDessus)).cap, avant);
    });

    testWidgets('la caméra reste immobile pour un petit déplacement, et se recadre si le chauffeur sort du cadre', (tester) async {
      final t = await ouvrir(tester);
      // Point de prise en charge : 14,6680 ; le chauffeur démarre ~1,1 km plus au nord.
      t.flux.add(direct(14.6780, lng0, t.heure.first));
      await avancer(tester, t.heure, const Duration(seconds: 2));
      final centre = t.carte.camera.center;
      final zoom = t.carte.camera.zoom;

      // 4 m plus près : rien ne bouge (ni centre, ni zoom).
      t.flux.add(direct(14.67796, lng0, t.heure.first));
      await avancer(tester, t.heure, const Duration(seconds: 2));
      expect(t.carte.camera.center, centre);
      expect(t.carte.camera.zoom, zoom);

      // Le chauffeur s'approche beaucoup (~100 m) : le zoom s'adapte pour le garder lisible.
      t.flux.add(direct(14.6689, lng0, t.heure.first));
      await avancer(tester, t.heure, const Duration(seconds: 2));
      expect(t.carte.camera.zoom, greaterThan(zoom));
    });

    testWidgets('si le client déplace la carte, on ne la lui reprend pas', (tester) async {
      final t = await ouvrir(tester);
      t.flux.add(direct(14.6780, lng0, t.heure.first));
      await avancer(tester, t.heure, const Duration(seconds: 2));
      await tester.drag(find.byType(FlutterMap), const Offset(80, 40));
      await tester.pump();
      final centre = t.carte.camera.center;

      t.flux.add(direct(14.6689, lng0, t.heure.first));
      await avancer(tester, t.heure, const Duration(seconds: 2));
      expect(t.carte.camera.center, centre);
      expect(find.byTooltip('Recentrer'), findsOneWidget);
    });

    testWidgets('"En direct" tant que ça arrive, puis "Signal faible" si plus rien depuis 15 s', (tester) async {
      final t = await ouvrir(tester);
      t.flux.add(direct(lat0, lng0, t.heure.first));
      await avancer(tester, t.heure, const Duration(seconds: 1));
      expect(find.text('En direct'), findsOneWidget);

      await avancer(tester, t.heure, const Duration(seconds: 6));
      expect(find.text('En direct'), findsOneWidget);

      await avancer(tester, t.heure, const Duration(seconds: 12));
      expect(find.text('En direct'), findsNothing);
      expect(find.text('Signal faible'), findsOneWidget);

      // Une nouvelle position et le direct revient.
      t.flux.add(direct(lat0, lng0, t.heure.first));
      await avancer(tester, t.heure, const Duration(seconds: 1));
      expect(find.text('En direct'), findsOneWidget);
    });
  });
}
