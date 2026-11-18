import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/compte/presentation/compte_tab_page.dart';
import 'package:sprint/features/compte/presentation/favoris_page.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/portefeuille/data/portefeuille_service.dart';

/// Aucun accès Firebase : le solde est piloté par le test.
class _Portefeuille extends PortefeuilleService {
  @override
  Stream<Portefeuille> streamPortefeuille(String uid) => Stream.value(const Portefeuille());
}

class _Courses extends CourseService {
  _Courses(this.liste);
  final List<CourseFirestore> liste;

  @override
  Stream<List<CourseFirestore>> streamCoursesClient(String clientId) => Stream.value(liste);
}

class _CoursesEnPanne extends CourseService {
  @override
  Stream<List<CourseFirestore>> streamCoursesClient(String clientId) => Stream.error(Exception('hors ligne'));
}

CourseFirestore _course(String id, String statut) => CourseFirestore(
      id: id,
      clientId: 'awa',
      chauffeurId: 'moussa',
      statut: statut,
      type: 'PASSAGER',
      adresseDepart: 'Plateau',
      adresseArrivee: 'Almadies',
      prixFcfa: 3000,
      methodePaiement: 'PORTEFEUILLE',
      timestamp: DateTime(2026, 11, 10),
    );

/// Le texte de la tuile `label` et sa valeur sont dans le même StatTile.
String? _valeur(WidgetTester tester, String label) {
  final tuile = find.ancestor(of: find.text(label), matching: find.byType(Column));
  if (tuile.evaluate().isEmpty) return null;
  final textes = find.descendant(of: tuile.first, matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).toList();
  return textes.firstWhere((t) => t != label, orElse: () => null);
}

Future<void> _ouvrir(WidgetTester tester, CompteTabPage page) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('Compte : statistiques du client', () {
    testWidgets('compte réel : Courses = courses terminées seulement ; Note et Réservations absentes ; Favoris à 0', (tester) async {
      await _ouvrir(
        tester,
        CompteTabPage(
          service: _Portefeuille(),
          clientId: 'awa',
          profil: Stream.value(null),
          courses: _Courses([
            _course('1', StatutCourse.terminee),
            _course('2', StatutCourse.terminee),
            _course('3', StatutCourse.annulee),
            _course('4', StatutCourse.enCours),
          ]),
        ),
      );

      expect(_valeur(tester, 'Courses'), '2');
      expect(_valeur(tester, 'Favoris'), '0');
      expect(find.text('Note'), findsNothing);
      expect(find.text('Réservations'), findsNothing);
      // Les valeurs de démonstration n'apparaissent jamais pour un compte réel.
      expect(find.text('4.8'), findsNothing);
      expect(find.text('23'), findsNothing);
      expect(find.text('3'), findsNothing);
    });

    testWidgets('compte neuf : 0 course', (tester) async {
      await _ouvrir(
        tester,
        CompteTabPage(service: _Portefeuille(), clientId: 'awa', profil: Stream.value(null), courses: _Courses(const [])),
      );
      expect(_valeur(tester, 'Courses'), '0');
    });

    testWidgets('lecture impossible : « – », jamais un chiffre inventé', (tester) async {
      await _ouvrir(
        tester,
        CompteTabPage(service: _Portefeuille(), clientId: 'awa', profil: Stream.value(null), courses: _CoursesEnPanne()),
      );
      expect(_valeur(tester, 'Courses'), '–');
      expect(tester.takeException(), isNull);
    });

    testWidgets('mode démonstration : les quatre statistiques de démonstration restent', (tester) async {
      await _ouvrir(tester, CompteTabPage(demo: true, profil: Stream.value(null)));
      for (final label in ['Note', 'Courses', 'Réservations']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // « Favoris » est aussi une entrée du menu : tuile + entrée.
      expect(find.text('Favoris'), findsNWidgets(2));
    });
  });

  group('Favoris', () {
    testWidgets('compte réel : aucune fausse adresse', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: FavorisPage(demo: false)));
      await tester.pump();
      expect(find.text('Aucune adresse enregistrée'), findsOneWidget);
      expect(find.text('Maison'), findsNothing);
      expect(find.text('Travail'), findsNothing);
    });

    testWidgets('mode démonstration : adresses d\'exemple', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: FavorisPage()));
      await tester.pump();
      expect(find.text('Maison'), findsOneWidget);
    });
  });
}
