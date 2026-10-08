import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/core/widgets/onyx_vert.dart';
import 'package:sprint/features/activite/presentation/activite_tab_page.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/messages/data/chat_service.dart';
import 'package:sprint/features/messages/presentation/messagerie_chat_page.dart';
import 'package:sprint/features/messages/presentation/messages_tab_page.dart';

class _Courses extends CourseService {
  @override
  Stream<List<CourseFirestore>> streamCoursesClient(String clientId) => Stream.value([
        CourseFirestore(
          id: 'c1',
          clientId: 'awa',
          chauffeurId: 'moussa',
          statut: StatutCourse.acceptee,
          type: 'PASSAGER',
          adresseDepart: 'Plateau',
          adresseArrivee: 'Almadies',
          prixFcfa: 3000,
          methodePaiement: 'WAVE',
          timestamp: DateTime(2026, 9, 30),
        ),
      ]);
}

class _Chat extends ChatService {
  @override
  Stream<List<ChatMessageFirestore>> streamMessages(String chatId) => Stream.value([
        ChatMessageFirestore(id: '1', senderId: 'moussa', text: 'J\'arrive', timestamp: DateTime(2026, 9, 30, 10)),
        ChatMessageFirestore(id: '2', senderId: 'awa', text: 'Je suis là', timestamp: DateTime(2026, 9, 30, 10, 1)),
      ]);

  @override
  Stream<ChatMessageFirestore?> streamDernierMessage(String chatId) => const Stream.empty();

  @override
  Future<Map<String, dynamic>?> chargerProfil(String uid) async => {'nom': 'Moussa Diop'};
}

void main() {
  void grandEcran(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('Activité : charte Onyx & Vert (fond Onyx, onglets pilule verte à texte Onyx, cartes verre)', (tester) async {
    grandEcran(tester);
    await tester.pumpWidget(MaterialApp(home: ActiviteTabPage(courseService: _Courses(), clientId: 'awa')));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ThemeOnyxVert), findsOneWidget);
    expect(find.byType(FondOnyxVert), findsOneWidget);
    expect(find.byType(CarteVerre), findsWidgets);
    final barre = tester.widget<TabBar>(find.byType(TabBar));
    expect(barre.labelColor, AppColors.onyx);
    expect((barre.indicator! as BoxDecoration).gradient, AppColors.degradeAction);
    expect(find.text('Suivre ma course'), findsOneWidget);
  });

  testWidgets('Livraison vide : carrousel horizontal de cartes (Colis, Repas, Courses) au-dessus du bouton', (tester) async {
    grandEcran(tester);
    await tester.pumpWidget(MaterialApp(home: ActiviteTabPage(courseService: _Courses(), clientId: 'awa')));
    await tester.pump();
    // Course immédiate : pas de carrousel.
    expect(find.byKey(const ValueKey('carrousel-livrables')), findsNothing);

    await tester.tap(find.text('Livraison'));
    await tester.pumpAndSettle();
    final carrousel = find.byKey(const ValueKey('carrousel-livrables'));
    expect(carrousel, findsOneWidget);
    expect(tester.widget<ListView>(carrousel).scrollDirection, Axis.horizontal);
    for (final libelle in ['Colis', 'Repas', 'Courses']) {
      expect(find.descendant(of: carrousel, matching: find.text(libelle)), findsOneWidget);
    }
    expect(find.text('Cadeaux'), findsNothing);
    expect(tester.getBottomLeft(carrousel).dy, lessThan(tester.getTopLeft(find.text('Envoyer un colis')).dy));
    // Les photos embarquées sont chargées (ou, si l'une manquait, le pictogramme
    // de repli la remplacerait) : jamais d'erreur.
    expect(find.descendant(of: carrousel, matching: find.byType(Image)), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Messages : conversation en carte verre, avatar Onyx cerclé de vert', (tester) async {
    grandEcran(tester);
    await tester.pumpWidget(MaterialApp(
      home: MessagesTabPage(courseService: _Courses(), chatService: _Chat(), monUid: 'awa'),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ThemeOnyxVert), findsOneWidget);
    expect(find.byType(CarteVerre), findsWidgets);
    expect(find.text('Moussa Diop'), findsOneWidget);
    expect(find.text('Course en cours · Almadies'), findsOneWidget);
  });

  testWidgets('Chat : mes messages en vert à texte Onyx, ceux du chauffeur en verre sombre, envoi vert', (tester) async {
    grandEcran(tester);
    await tester.pumpWidget(MaterialApp(
      home: MessagerieChatPage(
        interlocuteurUid: 'moussa',
        interlocuteurNom: 'Moussa Diop',
        interlocuteurSousTitre: 'Chauffeur Sprint',
        chatService: _Chat(),
        monUid: 'awa',
      ),
    ));
    await tester.pump();
    await tester.pump();
    Color? fond(String texte) {
      final bulle = find.ancestor(of: find.text(texte), matching: find.byType(Container)).first;
      return ((tester.widget<Container>(bulle).decoration!) as BoxDecoration).color;
    }

    expect(fond('Je suis là'), AppColors.vert);
    expect(fond('J\'arrive'), AppColors.carteHaute);
  });
}
