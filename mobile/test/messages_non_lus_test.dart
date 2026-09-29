import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sprint/core/navigation/home_shell_page.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/messages/data/chat_service.dart';
import 'package:sprint/features/messages/data/messages_non_lus.dart';
import 'package:sprint/features/messages/presentation/messages_tab_page.dart';
import 'package:sprint/features/messages/presentation/widgets/pastille_non_lus.dart';

ChatMessageFirestore _msg(String id, String auteur, [String texte = 'salut']) =>
    ChatMessageFirestore(id: id, senderId: auteur, text: texte, timestamp: DateTime(2026, 9, 29));

class _Chat extends ChatService {
  final flux = StreamController<List<ChatMessageFirestore>>.broadcast();
  final ecoutes = <String>[];

  @override
  Stream<List<ChatMessageFirestore>> streamMessages(String chatId) {
    ecoutes.add(chatId);
    return flux.stream;
  }

  @override
  Stream<ChatMessageFirestore?> streamDernierMessage(String chatId) => const Stream.empty();

  @override
  Future<Map<String, dynamic>?> chargerProfil(String uid) async => {'nom': 'Moussa Diop'};
}

CourseFirestore _course(String statut, {String? chauffeurId = 'moussa'}) => CourseFirestore(
      id: 'c1',
      clientId: 'awa',
      chauffeurId: chauffeurId,
      statut: statut,
      type: 'PASSAGER',
      adresseDepart: 'Plateau',
      adresseArrivee: 'Almadies',
      prixFcfa: 3000,
      methodePaiement: 'WAVE',
      timestamp: DateTime(2026, 9, 29),
    );

class _Courses extends CourseService {
  final flux = StreamController<List<CourseFirestore>>.broadcast();

  @override
  Stream<List<CourseFirestore>> streamCoursesClient(String clientId) => flux.stream;
}

Future<void> _laisser() => Future<void>.delayed(Duration.zero);

void main() {
  late _Chat chat;
  late int alertes;
  late MessagesNonLus nonLus;

  setUp(() {
    chat = _Chat();
    alertes = 0;
    nonLus = MessagesNonLus(alerte: () => alertes++);
  });
  tearDown(() {
    nonLus.dispose();
    chat.flux.close();
  });

  void suivre() => nonLus.suivre(chatService: chat, monUid: 'awa', interlocuteurUid: 'moussa');

  group('Compteur de messages non lus', () {
    test('à l\'ouverture : les messages du chauffeur restés sans réponse comptent, sans son', () async {
      suivre();
      chat.flux.add([_msg('1', 'moussa'), _msg('2', 'awa'), _msg('3', 'moussa'), _msg('4', 'moussa')]);
      await _laisser();
      expect(nonLus.nonLus, 2);
      expect(alertes, 0);
    });

    test('déjà répondu au dernier message : rien de non lu', () async {
      suivre();
      chat.flux.add([_msg('1', 'moussa'), _msg('2', 'awa')]);
      await _laisser();
      expect(nonLus.nonLus, 0);
    });

    test('message reçu en direct : +1, un son+vibration, publié pour le bandeau', () async {
      suivre();
      final recus = <String>[];
      nonLus.nouveauxMessages.listen((m) => recus.add(m.text));
      chat.flux.add([]);
      await _laisser();

      chat.flux.add([_msg('1', 'moussa', 'J\'arrive')]);
      await _laisser();
      expect(nonLus.nonLus, 1);
      expect(alertes, 1);
      expect(recus, ['J\'arrive']);
    });

    test('plusieurs messages d\'un coup (reconnexion) : tous comptés, un seul signal sonore', () async {
      suivre();
      chat.flux.add([]);
      await _laisser();
      chat.flux.add([_msg('1', 'moussa'), _msg('2', 'moussa'), _msg('3', 'moussa')]);
      await _laisser();
      expect(nonLus.nonLus, 3);
      expect(alertes, 1);
    });

    test('deux messages rapprochés dans deux émissions : un seul son (pas de vacarme)', () async {
      suivre();
      chat.flux.add([]);
      await _laisser();
      chat.flux.add([_msg('1', 'moussa')]);
      await _laisser();
      chat.flux.add([_msg('1', 'moussa'), _msg('2', 'moussa')]);
      await _laisser();
      expect(nonLus.nonLus, 2);
      expect(alertes, 1);
    });

    test('ses propres messages et les réémissions du même message : ignorés', () async {
      suivre();
      chat.flux.add([]);
      await _laisser();
      chat.flux.add([_msg('1', 'awa')]);
      await _laisser();
      chat.flux.add([_msg('1', 'awa')]);
      await _laisser();
      expect(nonLus.nonLus, 0);
      expect(alertes, 0);
      chat.flux.add([_msg('1', 'awa'), _msg('2', 'moussa')]);
      await _laisser();
      chat.flux.add([_msg('1', 'awa'), _msg('2', 'moussa')]);
      await _laisser();
      expect(nonLus.nonLus, 1);
      expect(alertes, 1);
    });

    test('conversation ouverte : ni compteur ni son ; fermée : ça repart', () async {
      suivre();
      chat.flux.add([_msg('0', 'moussa')]);
      await _laisser();
      expect(nonLus.nonLus, 1);

      nonLus.ouvrirConversation('moussa');
      expect(nonLus.nonLus, 0);
      chat.flux.add([_msg('0', 'moussa'), _msg('1', 'moussa')]);
      await _laisser();
      expect(nonLus.nonLus, 0);
      expect(alertes, 0);

      nonLus.fermerConversation('moussa');
      await _laisser();
      chat.flux.add([_msg('0', 'moussa'), _msg('1', 'moussa'), _msg('2', 'moussa')]);
      await _laisser();
      expect(nonLus.nonLus, 1);
      expect(alertes, 1);
    });

    test('ouvrir la conversation d\'un autre que le chauffeur suivi : sans effet', () async {
      suivre();
      chat.flux.add([_msg('0', 'moussa')]);
      await _laisser();
      nonLus.ouvrirConversation('inconnu');
      expect(nonLus.nonLus, 1);
      expect(nonLus.conversationOuverte, isFalse);
    });

    test('suivre deux fois le même chauffeur : une seule écoute ; fin de course : tout à zéro', () async {
      suivre();
      suivre();
      expect(chat.ecoutes, ['awa_moussa']);
      chat.flux.add([_msg('0', 'moussa')]);
      await _laisser();
      expect(nonLus.nonLus, 1);

      nonLus.arreter();
      expect(nonLus.nonLus, 0);
      expect(nonLus.interlocuteurUid, isNull);
      chat.flux.add([_msg('0', 'moussa'), _msg('1', 'moussa')]);
      await _laisser();
      expect(nonLus.nonLus, 0);
      expect(alertes, 0);
    });

    test('libellé de la pastille : 9+ au-delà de 9', () {
      expect(libelleNonLus(1), '1');
      expect(libelleNonLus(9), '9');
      expect(libelleNonLus(10), '9+');
    });
  });

  group('Pastille rouge', () {
    Widget hote(int nombre) => MaterialApp(
          home: Scaffold(body: Center(child: PastilleNonLus(nombre: nombre, child: const Icon(Icons.chat)))),
        );

    testWidgets('zéro : aucune pastille', (tester) async {
      await tester.pumpWidget(hote(0));
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('rouge avec le nombre, 9+ au-delà, lisible par les lecteurs d\'écran', (tester) async {
      final semantique = tester.ensureSemantics();
      await tester.pumpWidget(hote(3));
      expect(find.text('3'), findsOneWidget);
      expect(tester.widget<Badge>(find.byType(Badge)).backgroundColor, PastilleNonLus.rouge);
      expect(find.bySemanticsLabel(RegExp('3 messages non lus')), findsOneWidget);
      await tester.pumpWidget(hote(1));
      expect(find.bySemanticsLabel(RegExp('1 message non lu')), findsOneWidget);
      await tester.pumpWidget(hote(14));
      expect(find.text('9+'), findsOneWidget);
      semantique.dispose();
    });
  });

  testWidgets('onglet Messages : pastille sur la ligne de la conversation', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final courses = _Courses();
    addTearDown(courses.flux.close);
    suivre();
    chat.flux.add([_msg('1', 'moussa'), _msg('2', 'moussa')]);
    await tester.pump();

    await tester.pumpWidget(MaterialApp(
      home: MessagesTabPage(courseService: courses, chatService: chat, monUid: 'awa', messagesNonLus: nonLus),
    ));
    courses.flux.add([_course(StatutCourse.acceptee)]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Moussa Diop'), findsOneWidget);
    expect(find.descendant(of: find.byType(Badge), matching: find.text('2')), findsOneWidget);

    // Ouvrir la conversation : la pastille disparaît.
    await tester.tap(find.text('Moussa Diop'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(nonLus.nonLus, 0);
    expect(find.descendant(of: find.byType(Badge), matching: find.text('2')), findsNothing);
  });

  group('Coquille du client (barre du bas)', () {
    late _Courses courses;

    Future<void> afficher(WidgetTester tester) async {
      // Police de test (Ahem) bien plus large que la vraie : surface élargie.
      tester.view.physicalSize = const Size(640, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      courses = _Courses();
      addTearDown(courses.flux.close);
      final routeur = GoRouter(
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => HomeShellPage(
              navigationShell: shell,
              courseService: courses,
              chatService: chat,
              messagesNonLus: nonLus,
              monUid: 'awa',
            ),
            branches: [
              for (final chemin in ['/', '/activite', '/messages', '/compte'])
                StatefulShellBranch(routes: [
                  GoRoute(path: chemin, builder: (_, __) => Center(child: Text('page $chemin'))),
                ]),
            ],
          ),
        ],
      );
      addTearDown(routeur.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: routeur));
      await tester.pump();
    }

    testWidgets('sur un autre onglet : message du chauffeur -> son+vibration et pastille sur "Messages"', (tester) async {
      await afficher(tester);
      final onglet = find.ancestor(of: find.text('Messages'), matching: find.byType(InkWell));
      expect(find.descendant(of: onglet, matching: find.byType(Badge)), findsNothing);

      // Course acceptée : la coquille suit la conversation avec ce chauffeur.
      courses.flux.add([_course(StatutCourse.acceptee)]);
      await tester.pump();
      expect(chat.ecoutes, ['awa_moussa']);
      chat.flux.add([]);
      await tester.pump();

      chat.flux.add([_msg('1', 'moussa', 'Je suis arrivé')]);
      await tester.pump();
      expect(alertes, 1);
      expect(find.descendant(of: onglet, matching: find.text('1')), findsOneWidget);

      chat.flux.add([_msg('1', 'moussa'), _msg('2', 'moussa')]);
      await tester.pump(const Duration(seconds: 2));
      expect(find.descendant(of: onglet, matching: find.text('2')), findsOneWidget);
    });

    testWidgets('course terminée : le compteur disparaît', (tester) async {
      await afficher(tester);
      courses.flux.add([_course(StatutCourse.acceptee)]);
      await tester.pump();
      chat.flux.add([_msg('1', 'moussa'), _msg('2', 'moussa')]);
      await tester.pump();
      expect(nonLus.nonLus, 2);

      courses.flux.add([_course(StatutCourse.terminee)]);
      await tester.pump();
      expect(nonLus.nonLus, 0);
      final onglet = find.ancestor(of: find.text('Messages'), matching: find.byType(InkWell));
      expect(find.descendant(of: onglet, matching: find.byType(Badge)), findsNothing);
    });
  });
}
