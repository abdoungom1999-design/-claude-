import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/evaluations/data/evaluation_service.dart';
import 'package:sprint/features/evaluations/presentation/evaluation_course.dart';

final _course = CourseFirestore(
  id: 'course-1',
  clientId: 'client',
  chauffeurId: 'moussa',
  statut: StatutCourse.terminee,
  type: 'PASSAGER',
  adresseDepart: 'Plateau',
  adresseArrivee: 'Almadies',
  prixFcfa: 3000,
  methodePaiement: 'WAVE',
  timestamp: DateTime(2026, 9, 27),
);

class _EvaluationFactice extends EvaluationService {
  _EvaluationFactice({this.deja = false, this.echec = false});

  final bool deja;
  final bool echec;
  final envois = <(int, String?)>[];

  @override
  Future<bool> dejaEvaluee(String courseId) async => deja;

  @override
  Future<void> evaluer({required CourseFirestore course, required int note, String? commentaire}) async {
    if (echec) throw Exception('permission-denied');
    envois.add((note, commentaire));
  }
}

Future<List<String>> _afficher(WidgetTester tester, EvaluationService service) async {
  final retours = <String>[];
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: EvaluationCourse(
        course: _course,
        nomChauffeur: 'Moussa Diop',
        onTerminer: () => retours.add('accueil'),
        service: service,
      ),
    ),
  ));
  await tester.pump();
  return retours;
}

FilledButton _boutonEnvoyer(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, "Envoyer l'évaluation"));

void main() {
  group('Note moyenne', () {
    test('moyenne à une décimale, "Nouveau chauffeur" sans avis', () {
      final note = NoteChauffeur.depuisProfil({'noteSomme': 43, 'noteNombre': 9});
      expect(note.moyenne, closeTo(4.78, 0.01));
      expect(note.moyenneTexte, '4,8');
      expect(note.nombreTexte, '9 avis');
      expect(NoteChauffeur.depuisProfil({'nom': 'Awa'}).aDesAvis, isFalse);
      expect(NoteChauffeur.depuisProfil(null).nombreTexte, '0 avis');
    });

    testWidgets('badge affiché au client', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Column(children: [
          BadgeNoteChauffeur(note: NoteChauffeur.depuisProfil({'noteSomme': 43, 'noteNombre': 9})),
          BadgeNoteChauffeur(note: NoteChauffeur.depuisProfil({})),
        ]),
      ));
      expect(find.text('4,8'), findsOneWidget);
      expect(find.text(' · 9 avis'), findsOneWidget);
      expect(find.text('Nouveau chauffeur'), findsOneWidget);
    });
  });

  group('Écran d\'évaluation de fin de course', () {
    testWidgets('noter 4 étoiles avec un avis, puis retour à l\'accueil', (tester) async {
      final service = _EvaluationFactice();
      final retours = await _afficher(tester, service);

      expect(find.text('Comment s\'est passée votre course avec Moussa Diop ?'), findsOneWidget);
      expect(_boutonEnvoyer(tester).onPressed, isNull, reason: 'pas de note, pas d\'envoi');

      await tester.tap(find.byTooltip('4 étoiles'));
      await tester.pump();
      expect(find.text('Bien'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));

      await tester.enterText(find.byType(TextField), '  Très ponctuel  ');
      await tester.tap(find.text("Envoyer l'évaluation"));
      await tester.pumpAndSettle();

      expect(service.envois, [(4, '  Très ponctuel  ')]);
      expect(find.text('Merci pour votre avis !'), findsOneWidget);
      await tester.tap(find.text("Retour à l'accueil"));
      expect(retours, ['accueil']);
    });

    testWidgets('"Ignorer" ferme sans rien envoyer', (tester) async {
      final service = _EvaluationFactice();
      final retours = await _afficher(tester, service);

      await tester.tap(find.byTooltip('5 étoiles'));
      await tester.pump();
      await tester.tap(find.text('Ignorer'));
      expect(retours, ['accueil']);
      expect(service.envois, isEmpty);
    });

    testWidgets('course déjà notée : remerciement direct, pas de seconde note', (tester) async {
      await _afficher(tester, _EvaluationFactice(deja: true));
      await tester.pump();
      expect(find.text('Merci pour votre avis !'), findsOneWidget);
      expect(find.byTooltip('1 étoile'), findsNothing);
    });

    testWidgets('envoi refusé : message d\'erreur, la note est conservée', (tester) async {
      await _afficher(tester, _EvaluationFactice(echec: true));
      await tester.tap(find.byTooltip('3 étoiles'));
      await tester.pump();
      await tester.tap(find.text("Envoyer l'évaluation"));
      await tester.pumpAndSettle();
      expect(find.text("Votre avis n'a pas pu être envoyé. Réessayez."), findsOneWidget);
      expect(find.text('Correct'), findsOneWidget);
    });
  });
}
