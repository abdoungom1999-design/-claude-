import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

Future<StreamController<PositionChauffeurDirect?>> _afficher(WidgetTester tester, CourseFirestore course) async {
  final flux = StreamController<PositionChauffeurDirect?>();
  addTearDown(flux.close);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SuiviApproche(course: course, positions: flux.stream)),
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
      expect(find.byIcon(Icons.two_wheeler_rounded), findsNothing); // pas encore de chauffeur sur la carte

      flux.add(_position(14.6778, -17.4380));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('Votre chauffeur arrive dans ~4 min'), findsOneWidget);
      expect(find.text('À 1,2 km de vous'), findsOneWidget);
      // Marqueur du chauffeur sur la carte, en plus de celui du point de départ.
      expect(find.byIcon(Icons.two_wheeler_rounded), findsOneWidget);
      expect(find.byIcon(Icons.person_pin_circle_rounded), findsOneWidget);

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
      final avant = tester.getCenter(find.byIcon(Icons.two_wheeler_rounded).last);

      flux.add(_position(14.6740, -17.4380));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final pendant = tester.getCenter(find.byIcon(Icons.two_wheeler_rounded).last);
      await tester.pump(const Duration(milliseconds: 700));
      final apres = tester.getCenter(find.byIcon(Icons.two_wheeler_rounded).last);

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
}
