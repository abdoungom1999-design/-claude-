import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/client/presentation/suivi_course_page.dart';
import 'package:sprint/features/client/presentation/widgets/carte_chauffeur.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/position_chauffeur.dart';
import 'package:sprint/features/messages/data/chat_service.dart';

const _profilComplet = {
  'nom': 'Moussa Diop',
  'telephone': '+221770000001',
  'role': 'conducteur',
  'vehiculeId': 'Honda CB125 (2021)',
  'plaqueImmatriculation': 'DK-4821-AB',
  'noteSomme': 47,
  'noteNombre': 10,
};

Widget _carte(
  Map<String, dynamic>? profil, {
  bool clientABord = false,
  bool erreur = false,
  VoidCallback? onReessayer,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CarteChauffeur(profil: profil, clientABord: clientABord, erreur: erreur, onReessayer: onReessayer),
        ),
      ),
    );

CourseFirestore _course(String statut) => CourseFirestore(
      id: 'c1',
      clientId: 'awa',
      chauffeurId: 'moussa',
      statut: statut,
      type: 'PASSAGER',
      adresseDepart: 'Plateau',
      adresseArrivee: 'Almadies',
      prixFcfa: 3000,
      methodePaiement: 'WAVE',
      timestamp: DateTime(2026, 9, 29),
    );

class _Courses extends CourseService {
  _Courses(this.flux);

  final Stream<CourseFirestore?> flux;

  @override
  Stream<CourseFirestore?> streamCourse(String courseId) => flux;

  @override
  Stream<PositionChauffeurDirect?> streamPositionChauffeur(String chauffeurId) => const Stream.empty();
}

/// Profil du chauffeur contrôlé par le test : une file de réponses (ou d'échecs).
class _Chat extends ChatService {
  _Chat(this.reponses);

  final List<Future<Map<String, dynamic>?> Function()> reponses;
  var appels = 0;

  @override
  Future<Map<String, dynamic>?> chargerProfil(String uid) => reponses[appels++]();

  @override
  Stream<ChatMessageFirestore?> streamDernierMessage(String chatId) => const Stream.empty();
}

void main() {
  group('Carte du chauffeur assigné', () {
    testWidgets('nom complet, note, véhicule et plaque, dès que le chauffeur est trouvé', (tester) async {
      await tester.pumpWidget(_carte(_profilComplet));

      expect(find.text('Chauffeur trouvé · il arrive'), findsOneWidget);
      expect(find.text('Moussa Diop'), findsOneWidget);
      expect(find.text('MD'), findsOneWidget); // initiales
      expect(find.text('Honda CB125 (2021)'), findsOneWidget);
      expect(find.text('DK-4821-AB'), findsOneWidget);
      expect(find.text('4,7'), findsOneWidget);
      expect(find.text(' · 10 avis'), findsOneWidget);
      expect(find.text('Chauffeur Sprint'), findsNothing);
    });

    testWidgets('client à bord : "Course en cours"', (tester) async {
      await tester.pumpWidget(_carte(_profilComplet, clientABord: true));
      expect(find.text('Course en cours'), findsOneWidget);
      expect(find.text('Chauffeur trouvé · il arrive'), findsNothing);
      expect(find.text('Moussa Diop'), findsOneWidget);
    });

    testWidgets('véhicule et plaque absents : dit "non renseigné", rien d\'inventé', (tester) async {
      await tester.pumpWidget(_carte({'nom': 'Awa Fall'}));
      expect(find.text('Awa Fall'), findsOneWidget);
      expect(find.text('Non renseigné'), findsOneWidget);
      expect(find.text('Plaque non renseignée'), findsOneWidget);
      expect(find.text('Nouveau chauffeur'), findsOneWidget); // pas encore d'avis
    });

    testWidgets('écran très étroit : la plaque passe sous le véhicule, sans débordement', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_carte(_profilComplet));
      expect(find.text('DK-4821-AB'), findsOneWidget);
      expect(find.text('Honda CB125 (2021)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final plaque = tester.getTopLeft(find.text('DK-4821-AB'));
      final vehicule = tester.getTopLeft(find.text('Honda CB125 (2021)'));
      expect(plaque.dy, greaterThan(vehicule.dy));
    });

    testWidgets('profil vide : nom générique, pas de plantage', (tester) async {
      await tester.pumpWidget(_carte(const {}));
      expect(find.text('Chauffeur Sprint'), findsOneWidget);
      expect(find.text('CS'), findsOneWidget);
    });

    testWidgets('chargement : pas de faux nom pendant l\'attente', (tester) async {
      final semantique = tester.ensureSemantics();
      await tester.pumpWidget(_carte(null));
      expect(find.bySemanticsLabel('Chargement des informations du chauffeur'), findsOneWidget);
      expect(find.text('Chauffeur Sprint'), findsNothing);
      semantique.dispose();
    });

    testWidgets('lecture impossible : message et "Réessayer"', (tester) async {
      var essais = 0;
      await tester.pumpWidget(_carte(null, erreur: true, onReessayer: () => essais++));
      expect(find.textContaining("n'ont pas pu être chargées"), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      expect(essais, 1);
    });

    test('initiales : deux mots, un mot, espaces en trop, vide', () {
      expect(CarteChauffeur.initiales('Moussa Diop'), 'MD');
      expect(CarteChauffeur.initiales('Abdoulaye Ndiaye Sall'), 'AS');
      expect(CarteChauffeur.initiales('fatou'), 'F');
      expect(CarteChauffeur.initiales('  awa   sy  '), 'AS');
      expect(CarteChauffeur.initiales(''), '?');
    });
  });

  group('Écran de suivi : le chauffeur accepte', () {
    Future<void> afficher(WidgetTester tester, Stream<CourseFirestore?> flux, _Chat chat) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: SuiviCoursePage(
          courseId: 'c1',
          courseService: _Courses(flux),
          chatService: chat,
          monUid: 'awa',
          coucheFond: const SizedBox.shrink(),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('recherche, puis l\'identité complète apparaît dès l\'acceptation', (tester) async {
      final flux = StreamController<CourseFirestore?>();
      addTearDown(flux.close);
      final chat = _Chat([() async => _profilComplet]);
      await afficher(tester, flux.stream, chat);

      flux.add(_course(StatutCourse.enAttente));
      await tester.pump();
      expect(find.text("Recherche d'un chauffeur…"), findsOneWidget);
      expect(find.text('Moussa Diop'), findsNothing);

      flux.add(_course(StatutCourse.acceptee));
      await tester.pump();
      await tester.pump();
      expect(find.text('Chauffeur trouvé · il arrive'), findsOneWidget);
      expect(find.text('Moussa Diop'), findsOneWidget);
      expect(find.text('Honda CB125 (2021)'), findsOneWidget);
      expect(find.text('DK-4821-AB'), findsOneWidget);
      // Appeler et Discuter restent à portée.
      expect(find.text('Appeler'), findsOneWidget);
      expect(find.text('Discuter'), findsOneWidget);

      // Client à bord : même carte, autre état.
      flux.add(_course(StatutCourse.enCours));
      await tester.pump();
      await tester.pump();
      expect(find.text('Course en cours'), findsOneWidget);
      expect(find.text('Moussa Diop'), findsOneWidget);
    });

    testWidgets('lecture du profil en échec : "Réessayer" recharge l\'identité', (tester) async {
      final chat = _Chat([
        () async => throw Exception('réseau'),
        () async => _profilComplet,
      ]);
      await afficher(tester, Stream.value(_course(StatutCourse.acceptee)), chat);
      await tester.pump();

      expect(find.textContaining("n'ont pas pu être chargées"), findsOneWidget);
      expect(find.text('Chauffeur Sprint'), findsNothing);

      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining("n'ont pas pu être chargées"), findsNothing);
      expect(find.text('Moussa Diop'), findsOneWidget);
      expect(chat.appels, 2);
    });

    testWidgets('profil introuvable : on affiche ce qu\'on sait, sans chargement sans fin', (tester) async {
      final chat = _Chat([() async => null]);
      await afficher(tester, Stream.value(_course(StatutCourse.acceptee)), chat);
      await tester.pump();

      expect(find.text('Chauffeur Sprint'), findsOneWidget);
      expect(find.text('Non renseigné'), findsOneWidget);
      expect(find.text('Plaque non renseignée'), findsOneWidget);
    });
  });
}
