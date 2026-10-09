import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprint/core/maps/trace_utils.dart';
import 'package:sprint/features/conducteur/presentation/widgets/nouvelle_course_reelle_sheet.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/itineraire_service.dart';

const _depuis = LatLng(14.6781, -17.4458);
const _vers = LatLng(14.6928, -17.4467);

void main() {
  group('Itineraire (repli à vol d\'oiseau)', () {
    test('estimation : ligne droite, distance par la route estimée à vol d\'oiseau x 1,1', () {
      final estimation = Itineraire.estimation(_depuis, _vers);
      expect(estimation.estime, isTrue);
      expect(estimation.trace, [_depuis, _vers]);
      expect(estimation.distanceM, closeTo(TraceUtils.distanceM(_depuis, _vers) * 1.1, 1e-6));
      expect(estimation.distanceM, closeTo(1800, 30));
    });
  });

  group('ItineraireCloud (Cloud Function itineraireCourse)', () {
    final appels = <(String, Map<String, dynamic>)>[];

    ItineraireCloud service(Map<String, dynamic> reponse) => ItineraireCloud(appeler: (nom, donnees) async {
          appels.add((nom, donnees));
          return reponse;
        });

    setUp(appels.clear);

    test('envoie la course et la position du chauffeur, pas le point visé', () async {
      await service({'vers': 'client', 'distanceM': 1650, 'trace': '_p~iF~ps|U_ulLnnqC'})
          .calculer(courseId: 'c1', depuis: _depuis, vers: _vers);

      final (nom, donnees) = appels.single;
      expect(nom, 'itineraireCourse');
      expect(donnees, {
        'courseId': 'c1',
        'depuis': {'latitude': 14.6781, 'longitude': -17.4458},
      });
    });

    test('décode le tracé et la distance', () async {
      final itineraire = await service({'vers': 'client', 'distanceM': 1650, 'trace': '_p~iF~ps|U_ulLnnqC'})
          .calculer(courseId: 'c1', depuis: _depuis, vers: _vers);

      expect(itineraire.estime, isFalse);
      expect(itineraire.distanceM, 1650);
      expect(itineraire.trace, hasLength(2));
      expect(itineraire.trace.first.latitude, closeTo(38.5, 1e-9));
    });

    test('chauffeur arrivé (tracé vide) : ligne droite jusqu\'au point visé', () async {
      final itineraire = await service({'vers': 'client', 'distanceM': 12, 'trace': ''})
          .calculer(courseId: 'c1', depuis: _depuis, vers: _vers);

      expect(itineraire.trace, [_depuis, _vers]);
      expect(itineraire.distanceM, 12);
      expect(itineraire.estime, isFalse);
    });

    test('réponse invalide : exception, l\'appelant garde ce qu\'il avait', () async {
      final sansTrace = service({'vers': 'client', 'distanceM': 100});
      expect(() => sansTrace.calculer(courseId: 'c1', depuis: _depuis, vers: _vers), throwsFormatException);

      final traceTronquee = service({'vers': 'client', 'distanceM': 100, 'trace': '_p~iF~ps|'});
      expect(() => traceTronquee.calculer(courseId: 'c1', depuis: _depuis, vers: _vers), throwsFormatException);
    });
  });

  group('Proposition de course : distance jusqu\'au client', () {
    CourseFirestore course({PointsCourse? points}) => CourseFirestore(
          id: 'c1',
          clientId: 'client',
          chauffeurId: null,
          statut: StatutCourse.enAttente,
          type: 'PASSAGER',
          adresseDepart: 'Position GPS du client',
          adresseArrivee: 'Almadies, Dakar',
          prixFcfa: 3000,
          methodePaiement: 'WAVE',
          timestamp: DateTime(2026, 10, 9),
          points: points,
        );

    const points = PointsCourse(
      latitudeDepart: 14.6928,
      longitudeDepart: -17.4467,
      latitudeArrivee: 14.7450,
      longitudeArrivee: -17.5170,
    );

    Future<void> ouvrir(WidgetTester tester, CourseFirestore course, {LatLng? chauffeur}) async {
      tester.view.physicalSize =
          const Size(800, 900); // la police de test, très large, ferait déborder le prix à 390 px
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => afficherNouvelleCourseReelleSheet(
                  context,
                  course: course,
                  courseService: CourseService(),
                  chauffeurId: 'moussa',
                  positionChauffeur: chauffeur,
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('sans adresse écrite, le chauffeur voit à quelle distance est le client', (tester) async {
      await ouvrir(tester, course(points: points), chauffeur: _depuis);

      expect(find.text('Position GPS du client'), findsOneWidget);
      // ~1,6 km à vol d'oiseau, x 1,1 : 1,8 km ; 22 km/h : 5 min.
      expect(find.text('À ~1,8 km de vous · ~5 min'), findsOneWidget);
      expect(find.text('Almadies, Dakar'), findsOneWidget);
    });

    testWidgets('à moins d\'un kilomètre : en mètres', (tester) async {
      await ouvrir(tester, course(points: points), chauffeur: const LatLng(14.6900, -17.4467)); // ~300 m
      expect(find.textContaining(' m de vous · ~'), findsOneWidget);
    });

    testWidgets('position du chauffeur ou du client inconnue : rien d\'inventé', (tester) async {
      await ouvrir(tester, course(points: points));
      expect(find.textContaining('de vous'), findsNothing);
      expect(find.text('Position GPS du client'), findsOneWidget);
    });

    testWidgets('course sans coordonnées : pas de distance', (tester) async {
      await ouvrir(tester, course(), chauffeur: _depuis);
      expect(find.textContaining('de vous'), findsNothing);
    });
  });
}
