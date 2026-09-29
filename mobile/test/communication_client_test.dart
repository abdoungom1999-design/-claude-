import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/client/presentation/suivi_course_page.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/position_chauffeur.dart';
import 'package:sprint/features/messages/data/chat_service.dart';
import 'package:sprint/features/messages/data/messages_non_lus.dart';

final _course = CourseFirestore(
  id: 'c1',
  clientId: 'awa',
  chauffeurId: 'moussa',
  statut: StatutCourse.acceptee,
  type: 'PASSAGER',
  adresseDepart: 'Plateau',
  adresseArrivee: 'Almadies',
  prixFcfa: 3000,
  methodePaiement: 'WAVE',
  timestamp: DateTime(2026, 9, 27),
);

class _CoursesFactices extends CourseService {
  @override
  Stream<CourseFirestore?> streamCourse(String courseId) => Stream.value(_course);

  @override
  Stream<PositionChauffeurDirect?> streamPositionChauffeur(String chauffeurId) => const Stream.empty();
}

class _ChatFactice extends ChatService {
  final messages = StreamController<List<ChatMessageFirestore>>.broadcast();
  String? chatEcoute;

  @override
  Future<Map<String, dynamic>?> chargerProfil(String uid) async => {'nom': 'Moussa Diop', 'telephone': '+221770000001'};

  @override
  Stream<List<ChatMessageFirestore>> streamMessages(String chatId) {
    chatEcoute = chatId;
    return messages.stream;
  }
}

ChatMessageFirestore _message(String id, String auteur, String texte) =>
    ChatMessageFirestore(id: id, senderId: auteur, text: texte, timestamp: DateTime(2026, 9, 27));

void main() {
  testWidgets('client sur la carte : message affiché aussitôt, alerte son+vibration, pastille rouge avec compteur',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chat = _ChatFactice();
    addTearDown(chat.messages.close);
    var alertes = 0;
    final nonLus = MessagesNonLus(alerte: () => alertes++);
    addTearDown(nonLus.dispose);

    await tester.pumpWidget(MaterialApp(
      home: SuiviCoursePage(
        courseId: 'c1',
        courseService: _CoursesFactices(),
        chatService: chat,
        monUid: 'awa',
        coucheFond: const SizedBox.shrink(),
        messagesNonLus: nonLus,
      ),
    ));
    await tester.pump();
    await tester.pump();

    // Même conversation que celle ouverte par le chauffeur (UID triés).
    expect(chat.chatEcoute, 'awa_moussa');
    Finder pastille() => find.descendant(of: find.widgetWithText(OutlinedButton, 'Discuter'), matching: find.byType(Badge));

    chat.messages.add([]); // conversation vide à l'ouverture
    await tester.pump();
    expect(pastille(), findsNothing);
    expect(alertes, 0);

    chat.messages.add([_message('m1', 'moussa', "J'arrive dans 2 min")]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("Moussa Diop : J'arrive dans 2 min"), findsOneWidget);
    expect(find.text('Répondre'), findsOneWidget);
    expect(alertes, 1);
    expect(pastille(), findsOneWidget);
    expect(tester.widget<Badge>(pastille()).backgroundColor, const Color(0xFFE53935));
    expect(find.descendant(of: pastille(), matching: find.text('1')), findsOneWidget);

    // Son propre message ne déclenche rien de plus.
    chat.messages.add([
      _message('m1', 'moussa', "J'arrive dans 2 min"),
      _message('m2', 'awa', 'Ok, je descends'),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Ok, je descends'), findsNothing);
    expect(alertes, 1);
    expect(nonLus.nonLus, 1);
  });

  testWidgets('deux messages : le compteur passe à 2 ; ouvrir "Discuter" remet tout à zéro', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chat = _ChatFactice();
    addTearDown(chat.messages.close);
    final nonLus = MessagesNonLus(alerte: () {});
    addTearDown(nonLus.dispose);

    await tester.pumpWidget(MaterialApp(
      home: SuiviCoursePage(
        courseId: 'c1',
        courseService: _CoursesFactices(),
        chatService: chat,
        monUid: 'awa',
        coucheFond: const SizedBox.shrink(),
        messagesNonLus: nonLus,
      ),
    ));
    await tester.pump();
    await tester.pump();
    chat.messages.add([]);
    await tester.pump();

    final m1 = _message('m1', 'moussa', 'Bonjour');
    final m2 = _message('m2', 'moussa', 'Je suis devant');
    chat.messages.add([m1]);
    await tester.pump(const Duration(seconds: 2));
    chat.messages.add([m1, m2]);
    await tester.pump(const Duration(seconds: 2));
    final discuter = find.widgetWithText(OutlinedButton, 'Discuter');
    expect(find.descendant(of: discuter, matching: find.text('2')), findsOneWidget);

    await tester.tap(discuter);
    await tester.pump(const Duration(milliseconds: 600));
    expect(nonLus.nonLus, 0);
    expect(nonLus.conversationOuverte, isTrue);

    // Chat ouvert : un nouveau message ne compte pas (on le voit arriver).
    chat.messages.add([m1, m2, _message('m3', 'moussa', 'Vous êtes là ?')]);
    await tester.pump(const Duration(seconds: 2));
    expect(nonLus.nonLus, 0);

    // Retour sur la carte : plus de pastille.
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(nonLus.conversationOuverte, isFalse);
    expect(find.descendant(of: discuter, matching: find.byType(Badge)), findsNothing);
  });
}
