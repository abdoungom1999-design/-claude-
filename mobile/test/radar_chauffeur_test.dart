import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprint/features/conducteur/presentation/widgets/nouvelle_course_reelle_sheet.dart';
import 'package:sprint/features/courses/data/course_service.dart';

/// Ce que le serveur écrit dans le radar (`radar/{id}`, functions/src/radar.ts) :
/// des zones arrondies à ~150 m et des libellés, jamais l'adresse du client.
Map<String, dynamic> _documentRadar() => {
      'clientId': 'awa',
      'statut': 'en_attente',
      'type': 'PASSAGER',
      'adresseDepart': 'Zone de départ approximative (Dakar)',
      'adresseArrivee': "Zone d'arrivée approximative (Dakar)",
      'adressesMasquees': true,
      'latitudeDepart': 14.69278,
      'longitudeDepart': -17.44617,
      'departArrondi': true,
      'latitudeArrivee': 14.74533,
      'longitudeArrivee': -17.51307,
      'distanceKm': 10.2,
      'prixFcfa': 2300,
      'methodePaiement': 'WAVE',
      'timestamp': Timestamp.fromDate(DateTime(2026, 11, 13, 12)),
    };

/// Ce que le serveur écrit dans la course elle-même : l'adresse de la personne.
Map<String, dynamic> _documentCourse() => {
      ..._documentRadar(),
      'adresseDepart': '12 rue Carnot, Médina',
      'adresseArrivee': 'Aéroport Blaise Diagne',
      'adressesMasquees': null,
    }..remove('adressesMasquees');

class _Service extends CourseService {
  final acceptations = <(String, String, String)>[];
  bool gagne = true;

  @override
  Future<bool> accepterCourse({required String courseId, required String chauffeurId, required String clientId}) async {
    acceptations.add((courseId, chauffeurId, clientId));
    return gagne;
  }
}

Future<bool?> Function() _ouvrir(WidgetTester tester, CourseFirestore course, _Service service) {
  bool? resultat;
  bool termine = false;
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return () async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              resultat = await afficherNouvelleCourseReelleSheet(
                context,
                course: course,
                courseService: service,
                chauffeurId: 'moussa',
                positionChauffeur: const LatLng(14.70, -17.45),
              );
              termine = true;
            },
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return termine ? resultat : null;
  };
}

void main() {
  group('Radar : ce qu\'un chauffeur lit d\'une course avant de l\'avoir acceptée', () {
    test('un document du radar se lit comme une course : zones, pas d\'adresse, cases arrondies', () {
      final course = CourseFirestore.depuisDocument('c1', _documentRadar());
      expect(course.adressesMasquees, isTrue);
      expect(course.adresseDepart, 'Zone de départ approximative (Dakar)');
      expect(course.adresseArrivee, "Zone d'arrivée approximative (Dakar)");
      expect(course.departArrondi, isTrue);
      expect(course.clientId, 'awa', reason: 'nécessaire à la liaison créée à l\'acceptation');
      expect(course.prixFcfa, 2300);
      expect(course.statut, StatutCourse.enAttente);
      expect(course.points?.latitudeDepart, 14.69278);
      expect(course.points?.latitudeArrivee, 14.74533);
    });

    test('une vraie course garde son adresse et n\'est pas « masquée »', () {
      final course = CourseFirestore.depuisDocument('c1', _documentCourse());
      expect(course.adressesMasquees, isFalse);
      expect(course.adresseDepart, '12 rue Carnot, Médina');
      expect(course.adresseArrivee, 'Aéroport Blaise Diagne');
    });

    test('avec la position exacte, la course acceptée n\'est plus « masquée »', () {
      final exacte = CourseFirestore.depuisDocument('c1', _documentRadar()).avecDepartExact(
        const DepartExact(latitude: 14.69281, longitude: -17.44673),
      );
      expect(exacte.adressesMasquees, isFalse);
      expect(exacte.departArrondi, isFalse);
    });
  });

  group('Proposition de course du chauffeur', () {
    testWidgets('zones à la place des adresses, légende, et acceptation avec le client du radar', (tester) async {
      final service = _Service();
      final ouvrir = _ouvrir(tester, CourseFirestore.depuisDocument('radar1', _documentRadar()), service);
      await ouvrir();

      expect(find.text('Zone de départ approximative (Dakar)'), findsOneWidget);
      expect(find.text("Zone d'arrivée approximative (Dakar)"), findsOneWidget);
      expect(find.text("L'adresse exacte et le point précis s'affichent dès que vous acceptez."), findsOneWidget);

      await tester.tap(find.text('ACCEPTER'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.acceptations, [('radar1', 'moussa', 'awa')]);
      expect(find.text('ACCEPTER'), findsNothing, reason: 'la proposition se ferme une fois acceptée');
    });

    testWidgets('course prise entre-temps par un autre chauffeur : message clair, la proposition se ferme', (tester) async {
      final service = _Service()..gagne = false;
      final ouvrir = _ouvrir(tester, CourseFirestore.depuisDocument('radar1', _documentRadar()), service);
      await ouvrir();

      await tester.tap(find.text('ACCEPTER'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Cette course vient d\'être prise par un autre chauffeur.'), findsOneWidget);
      expect(find.text('ACCEPTER'), findsNothing);
    });

    testWidgets('une course sans zones masquées (ancienne proposition) : pas de légende', (tester) async {
      final service = _Service();
      final ouvrir = _ouvrir(tester, CourseFirestore.depuisDocument('c1', _documentCourse()), service);
      await ouvrir();

      expect(find.text('12 rue Carnot, Médina'), findsOneWidget);
      expect(find.textContaining("s'affichent dès que vous acceptez"), findsNothing);

      await tester.tap(find.text('Refuser'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.acceptations, isEmpty);
    });
  });
}
