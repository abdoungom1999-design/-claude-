import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/conducteur/presentation/tabs/conducteur_messages_tab.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/messages/data/chat_service.dart';
import 'package:sprint/features/messages/presentation/messagerie_chat_page.dart';
import 'package:sprint/features/messages/presentation/messages_tab_page.dart';

CourseFirestore _course(String id, String statut, {String? chauffeurId = 'moussa', String arrivee = 'Almadies'}) =>
    CourseFirestore(
      id: id,
      clientId: 'awa',
      chauffeurId: chauffeurId,
      statut: statut,
      type: 'PASSAGER',
      adresseDepart: 'Plateau',
      adresseArrivee: arrivee,
      prixFcfa: 3000,
      methodePaiement: 'WAVE',
      timestamp: DateTime(2026, 9, 29),
    );

class _Courses extends CourseService {
  _Courses({this.duClient = const [], this.duChauffeur});

  final List<CourseFirestore> duClient;
  final CourseFirestore? duChauffeur;

  @override
  Stream<List<CourseFirestore>> streamCoursesClient(String clientId) => Stream.value(duClient);

  @override
  Stream<CourseFirestore?> streamCourseActiveChauffeur(String chauffeurId) => Stream.value(duChauffeur);
}

class _Chat extends ChatService {
  final profilsLus = <String>[];
  bool profilRefuse = false;
  Object? erreurEnvoi;
  final envois = <(String, List<String>, String)>[];
  ChatMessageFirestore? dernier;

  final _profils = <String, Map<String, dynamic>>{
    'moussa': {'nom': 'Moussa Diop', 'telephone': '+221770000001'},
    'awa': {'nom': 'Awa Ndiaye', 'telephone': '+221770000009'},
  };

  @override
  Future<Map<String, dynamic>?> chargerProfil(String uid) async {
    profilsLus.add(uid);
    if (profilRefuse) throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    return _profils[uid];
  }

  @override
  Stream<ChatMessageFirestore?> streamDernierMessage(String chatId) => Stream.value(dernier);

  @override
  Stream<List<ChatMessageFirestore>> streamMessages(String chatId) => Stream.value(const []);

  @override
  Future<void> envoyerMessage({required String chatId, required List<String> participants, required String texte}) async {
    final erreur = erreurEnvoi;
    if (erreur != null) throw erreur;
    envois.add((chatId, participants, texte));
  }
}

void main() {
  test('Liaison : identifiant client_chauffeur et champs attendus par les règles Firestore', () {
    expect(Liaison.id(clientId: 'awa', chauffeurId: 'moussa'), 'awa_moussa');
    final donnees = Liaison.donnees(clientId: 'awa', chauffeurId: 'moussa', courseId: 'c1');
    // Exactement ces quatre champs (`hasOnly` dans firestore.rules).
    expect(donnees.keys.toSet(), {'clientId', 'chauffeurId', 'courseId', 'creeLe'});
    expect(donnees['clientId'], 'awa');
    expect(donnees['chauffeurId'], 'moussa');
    expect(donnees['courseId'], 'c1');
  });

  Future<void> afficher(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump();
    await tester.pump();
  }

  group('Messages du client : uniquement le chauffeur de sa course en cours', () {
    Widget onglet(_Courses courses, _Chat chat) => MessagesTabPage(courseService: courses, chatService: chat, monUid: 'awa');

    testWidgets('aucune course en cours : aucune conversation, et aucun profil lu', (tester) async {
      final chat = _Chat();
      await afficher(tester, onglet(_Courses(), chat));
      expect(find.text('Aucune conversation en cours'), findsOneWidget);
      expect(find.textContaining('dès qu\'il aura accepté votre course'), findsOneWidget);
      expect(chat.profilsLus, isEmpty);
    });

    testWidgets('course acceptée : le chauffeur assigné, et lui seul', (tester) async {
      final chat = _Chat();
      await afficher(tester, onglet(_Courses(duClient: [_course('c1', StatutCourse.acceptee)]), chat));
      expect(find.text('Moussa Diop'), findsOneWidget);
      expect(find.text('Course en cours · Almadies'), findsOneWidget);
      expect(find.text('Aucun message pour le moment'), findsOneWidget);
      expect(chat.profilsLus, ['moussa']);
    });

    testWidgets('courses terminées, annulées, en attente ou sans chauffeur : jamais listées', (tester) async {
      final chat = _Chat();
      await afficher(
        tester,
        onglet(
          _Courses(duClient: [
            _course('c1', StatutCourse.enCours, arrivee: 'Ngor'),
            _course('c2', StatutCourse.terminee, chauffeurId: 'ancien1'),
            _course('c3', StatutCourse.annulee, chauffeurId: 'ancien2'),
            _course('c4', StatutCourse.enAttente, chauffeurId: null),
          ]),
          chat,
        ),
      );
      expect(find.text('Course en cours · Ngor'), findsOneWidget);
      expect(find.textContaining('Course en cours'), findsOneWidget);
      // Aucun profil d'un ancien chauffeur n'est même demandé.
      expect(chat.profilsLus, ['moussa']);
    });

    testWidgets('profil refusé (course terminée entre-temps) : nom par défaut, pas de plantage', (tester) async {
      final chat = _Chat()..profilRefuse = true;
      await afficher(tester, onglet(_Courses(duClient: [_course('c1', StatutCourse.acceptee)]), chat));
      expect(find.text('Votre chauffeur'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dernier message affiché, et un tap ouvre le chat avec ce chauffeur', (tester) async {
      final chat = _Chat()..dernier = ChatMessageFirestore(senderId: 'moussa', text: 'J\'arrive !', timestamp: DateTime(2026, 9, 29));
      await afficher(tester, onglet(_Courses(duClient: [_course('c1', StatutCourse.acceptee)]), chat));
      expect(find.text('J\'arrive !'), findsOneWidget);

      await tester.tap(find.text('Moussa Diop'));
      await tester.pumpAndSettle();
      expect(find.byType(MessagerieChatPage), findsOneWidget);
      expect(find.text('Chauffeur Sprint'), findsOneWidget);
    });

    testWidgets('sans identifiant de client (non connecté) : messagerie indisponible', (tester) async {
      await afficher(tester, const MessagesTabPage());
      expect(find.text('Messagerie indisponible'), findsOneWidget);
    });
  });

  group('Messages du chauffeur : uniquement le client de sa course en cours', () {
    Widget onglet(_Courses courses, _Chat chat) =>
        ConducteurMessagesTab(courseService: courses, chatService: chat, monUid: 'moussa');

    testWidgets('sans course en cours : aucune conversation', (tester) async {
      final chat = _Chat();
      await afficher(tester, onglet(_Courses(), chat));
      expect(find.text('Aucune conversation en cours'), findsOneWidget);
      expect(chat.profilsLus, isEmpty);
    });

    testWidgets('course en cours : son client', (tester) async {
      final chat = _Chat();
      await afficher(tester, onglet(_Courses(duChauffeur: _course('c1', StatutCourse.enCours)), chat));
      expect(find.text('Awa Ndiaye'), findsOneWidget);
      expect(find.text('Course en cours · Plateau'), findsOneWidget);
      expect(chat.profilsLus, ['awa']);
    });
  });

  group('Chat : refus propres une fois la course terminée', () {
    Future<_Chat> ouvrir(WidgetTester tester, {bool profilRefuse = false, Object? erreurEnvoi}) async {
      final chat = _Chat()
        ..profilRefuse = profilRefuse
        ..erreurEnvoi = erreurEnvoi;
      await afficher(
        tester,
        MessagerieChatPage(
          interlocuteurUid: 'moussa',
          interlocuteurNom: 'Moussa Diop',
          interlocuteurSousTitre: 'Chauffeur Sprint',
          chatService: chat,
          monUid: 'awa',
        ),
      );
      return chat;
    }

    testWidgets('message envoyé pendant la course', (tester) async {
      final chat = await ouvrir(tester);
      await tester.enterText(find.byType(TextField), 'Je suis devant la pharmacie');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(chat.envois.single.$2, ['awa', 'moussa']);
      expect(chat.envois.single.$3, 'Je suis devant la pharmacie');
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('course terminée : message refusé, dit clairement, texte conservé', (tester) async {
      await ouvrir(tester, erreurEnvoi: FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
      await tester.enterText(find.byType(TextField), 'Merci pour la course');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('on ne peut écrire qu\'à l\'autre partie d\'une course en cours'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Merci pour la course');
    });

    testWidgets('réseau coupé : message d\'échec de connexion, texte conservé', (tester) async {
      await ouvrir(tester, erreurEnvoi: FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
      await tester.enterText(find.byType(TextField), 'Bonjour');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Vérifiez votre connexion'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Bonjour');
    });

    testWidgets('numéro illisible (course terminée) : "Appeler" le dit, sans planter', (tester) async {
      await ouvrir(tester, profilRefuse: true);
      await tester.tap(find.byTooltip('Appeler'));
      await tester.pump();
      expect(find.text('Numéro de téléphone indisponible.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
