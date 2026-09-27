import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/client/presentation/suivi_course_page.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/position_chauffeur.dart';
import 'package:sprint/features/messages/data/chat_service.dart';

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
  final dernierMessage = StreamController<ChatMessageFirestore?>();
  String? chatEcoute;

  @override
  Future<Map<String, dynamic>?> chargerProfil(String uid) async => {'nom': 'Moussa Diop', 'telephone': '+221770000001'};

  @override
  Stream<ChatMessageFirestore?> streamDernierMessage(String chatId) {
    chatEcoute = chatId;
    return dernierMessage.stream;
  }
}

ChatMessageFirestore _message(String id, String auteur, String texte) =>
    ChatMessageFirestore(id: id, senderId: auteur, text: texte, timestamp: DateTime(2026, 9, 27));

void main() {
  testWidgets('client sur la carte : le message du chauffeur s\'affiche aussitôt, badge sur "Discuter"', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chat = _ChatFactice();
    addTearDown(chat.dernierMessage.close);

    await tester.pumpWidget(MaterialApp(
      home: SuiviCoursePage(courseId: 'c1', courseService: _CoursesFactices(), chatService: chat, monUid: 'awa'),
    ));
    await tester.pump();
    await tester.pump();

    // Même conversation que celle ouverte par le chauffeur (UID triés).
    expect(chat.chatEcoute, 'awa_moussa');
    Badge pastille() => tester.widget<Badge>(
          find.descendant(of: find.widgetWithText(OutlinedButton, 'Discuter'), matching: find.byType(Badge)),
        );

    chat.dernierMessage.add(null); // conversation vide à l'ouverture
    await tester.pump();
    expect(pastille().isLabelVisible, isFalse);

    chat.dernierMessage.add(_message('m1', 'moussa', "J'arrive dans 2 min"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("Moussa Diop : J'arrive dans 2 min"), findsOneWidget);
    expect(find.text('Répondre'), findsOneWidget);
    expect(pastille().isLabelVisible, isTrue);

    // Son propre message ne déclenche rien de plus.
    chat.dernierMessage.add(_message('m2', 'awa', 'Ok, je descends'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Awa : Ok, je descends'), findsNothing);
    expect(find.textContaining('Ok, je descends'), findsNothing);
  });
}
