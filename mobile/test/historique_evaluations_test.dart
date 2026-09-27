import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/compte/presentation/courses_a_noter_page.dart';
import 'package:sprint/features/conducteur/presentation/tabs/conducteur_evaluations_tab.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/evaluations/data/evaluation_service.dart';

CourseFirestore _course(String id, String depart, DateTime quand) => CourseFirestore(
      id: id,
      clientId: 'client',
      chauffeurId: 'moussa',
      statut: StatutCourse.terminee,
      type: 'PASSAGER',
      adresseDepart: depart,
      adresseArrivee: 'Almadies',
      prixFcfa: 3000,
      methodePaiement: 'WAVE',
      timestamp: quand,
    );

class _ServiceFactice extends EvaluationService {
  _ServiceFactice({
    this.courses = const [],
    this.echecChargement = false,
    this.note = const NoteChauffeur(somme: 0, nombre: 0),
    this.avis = const [],
  });

  final List<CourseFirestore> courses;
  final bool echecChargement;
  final NoteChauffeur note;
  final List<EvaluationRecue> avis;
  final notees = <String, int>{};

  @override
  Future<List<CourseANoter>> coursesANoter(String clientId) async {
    if (echecChargement) throw Exception('hors connexion');
    return [
      for (final c in courses)
        if (!notees.containsKey(c.id)) CourseANoter(course: c, nomChauffeur: 'Moussa Diop'),
    ];
  }

  @override
  Future<bool> dejaEvaluee(String courseId) async => notees.containsKey(courseId);

  @override
  Future<void> evaluer({required CourseFirestore course, required int note, String? commentaire}) async {
    notees[course.id] = note;
  }

  @override
  Stream<NoteChauffeur> streamNoteChauffeur(String chauffeurId) => Stream.value(note);

  @override
  Stream<List<EvaluationRecue>> streamEvaluationsRecues(String chauffeurId) => Stream.value(avis);
}

Future<void> _afficher(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(480, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
}

void main() {
  group('Client : courses à noter', () {
    testWidgets('liste les courses terminées non notées ; noter en retard les retire de la liste', (tester) async {
      final service = _ServiceFactice(courses: [
        _course('c1', 'Plateau', DateTime(2026, 9, 25)),
        _course('c2', 'Médina', DateTime(2026, 9, 20)),
      ]);
      await _afficher(tester, CoursesANoterPage(service: service, clientId: 'client'));

      expect(find.text('2'), findsOneWidget); // avis en attente
      expect(find.text('Plateau → Almadies'), findsOneWidget);
      expect(find.textContaining('avec Moussa Diop'), findsNWidgets(2));
      expect(find.textContaining('25/09'), findsOneWidget);

      await tester.tap(find.text('Noter cette course').first);
      await tester.pumpAndSettle();
      expect(find.text('Noter votre course'), findsOneWidget);
      expect(find.text('Plus tard'), findsOneWidget);

      await tester.tap(find.byTooltip('5 étoiles'));
      await tester.pump();
      await tester.tap(find.text("Envoyer l'évaluation"));
      await tester.pumpAndSettle();
      expect(find.text('Merci pour votre avis !'), findsOneWidget);
      await tester.tap(find.text('Retour à la liste'));
      await tester.pumpAndSettle();

      expect(service.notees, {'c1': 5});
      expect(find.text('Plateau → Almadies'), findsNothing);
      expect(find.text('Médina → Almadies'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('"Plus tard" revient à la liste sans rien noter', (tester) async {
      final service = _ServiceFactice(courses: [_course('c1', 'Plateau', DateTime(2026, 9, 25))]);
      await _afficher(tester, CoursesANoterPage(service: service, clientId: 'client'));
      await tester.tap(find.text('Noter cette course'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();
      expect(service.notees, isEmpty);
      expect(find.text('Plateau → Almadies'), findsOneWidget);
    });

    testWidgets('tout est noté', (tester) async {
      await _afficher(tester, CoursesANoterPage(service: _ServiceFactice(), clientId: 'client'));
      expect(find.text('Tout est noté !'), findsOneWidget);
    });

    testWidgets('chargement impossible : message et "Réessayer"', (tester) async {
      await _afficher(tester, CoursesANoterPage(service: _ServiceFactice(echecChargement: true), clientId: 'client'));
      expect(find.text('Impossible de charger vos courses.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });
  });

  group('Chauffeur : avis reçus', () {
    testWidgets('note officielle, répartition et vrais commentaires (anonymes)', (tester) async {
      await _afficher(
        tester,
        ConducteurEvaluationsTab(
          chauffeurId: 'moussa',
          service: _ServiceFactice(
            note: const NoteChauffeur(somme: 14, nombre: 3),
            avis: [
              EvaluationRecue(courseId: 'a', note: 5, commentaire: 'Très ponctuel', creeLe: DateTime(2026, 9, 26)),
              EvaluationRecue(courseId: 'b', note: 5, creeLe: DateTime(2026, 9, 25)),
              EvaluationRecue(courseId: 'c', note: 4, commentaire: 'Bien', creeLe: DateTime(2026, 9, 24)),
            ],
          ),
        ),
      );

      expect(find.text('4,7'), findsOneWidget);
      expect(find.text('Basé sur 3 avis'), findsOneWidget);
      expect(find.text('Très ponctuel'), findsOneWidget);
      expect(find.text('Note sans commentaire.'), findsOneWidget);
      expect(find.text('Client Sprint'), findsNWidgets(3));
      expect(find.text('26/09/2026'), findsOneWidget);
      // Aucun faux avis de démonstration.
      expect(find.text('Compliments reçus'), findsNothing);
    });

    testWidgets('pas encore d\'avis', (tester) async {
      await _afficher(tester, ConducteurEvaluationsTab(chauffeurId: 'moussa', service: _ServiceFactice()));
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining("Pas encore d'avis"), findsOneWidget);
      expect(find.text('Avis récents'), findsNothing);
    });

    test('avis mal formé ignoré, commentaire vide = pas de commentaire', () {
      expect(EvaluationRecue.depuisDocument('x', {'commentaire': 'sans note'}), isNull);
      expect(EvaluationRecue.depuisDocument('x', {'note': 4, 'commentaire': '   '})!.commentaire, isNull);
    });
  });
}
