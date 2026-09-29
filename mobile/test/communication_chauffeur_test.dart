import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/conducteur/presentation/widgets/course_active_bandeau.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/messages/data/chat_service.dart';
import 'package:sprint/features/messages/data/detecteur_nouveaux_messages.dart';

ChatMessageFirestore _message(String id, String auteur, String texte) =>
    ChatMessageFirestore(id: id, senderId: auteur, text: texte, timestamp: DateTime(2026, 9, 27));

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

void main() {
  group('Nouveaux messages du client', () {
    test('le "Bonjour" du client arrivé pendant la course déclenche une alerte', () {
      final detecteur = DetecteurNouveauxMessages(interlocuteurUid: 'awa');
      expect(detecteur.recevoir(null), isFalse); // conversation vide à l'ouverture
      expect(detecteur.recevoir(_message('m1', 'awa', 'Bonjour')), isTrue);
      expect(detecteur.nonLu, isTrue);

      detecteur.marquerLu();
      expect(detecteur.nonLu, isFalse);
      // Réémission du même message (confirmation serveur) : pas de nouvelle alerte.
      expect(detecteur.recevoir(_message('m1', 'awa', 'Bonjour')), isFalse);
      expect(detecteur.nonLu, isFalse);
    });

    test('ses propres messages ne comptent pas ; un message déjà là à l\'ouverture = non lu sans alerte', () {
      final detecteur = DetecteurNouveauxMessages(interlocuteurUid: 'awa');
      expect(detecteur.recevoir(_message('m1', 'awa', 'Je suis devant')), isFalse);
      expect(detecteur.nonLu, isTrue);
      detecteur.marquerLu();
      expect(detecteur.recevoir(_message('m2', 'moussa', 'J\'arrive')), isFalse);
      expect(detecteur.nonLu, isFalse);
      expect(detecteur.recevoir(_message('m3', 'awa', 'Ok merci')), isTrue);
    });
  });

  group('Bandeau de course du chauffeur', () {
    testWidgets('"Appeler" et "Message" comme côté client, badge si message non lu', (tester) async {
      final appels = <String>[];
      Widget bandeau({required bool nonLu}) => MaterialApp(
            home: Scaffold(
              bottomNavigationBar: CourseActiveBandeau(
                course: _course,
                enCours: false,
                onAvancer: () => appels.add('avancer'),
                onAppeler: () => appels.add('appel'),
                onMessage: () => appels.add('message'),
                onNaviguer: () => appels.add('naviguer'),
                onAnnuler: () => appels.add('annuler'),
                messageNonLu: nonLu,
              ),
            ),
          );

      await tester.pumpWidget(bandeau(nonLu: false));
      await tester.tap(find.text('Appeler'));
      await tester.tap(find.text('Message'));
      expect(appels, ['appel', 'message']);

      Badge pastille() => tester.widget<Badge>(find.descendant(of: find.widgetWithText(OutlinedButton, 'Message'), matching: find.byType(Badge)));
      expect(pastille().isLabelVisible, isFalse);
      await tester.pumpWidget(bandeau(nonLu: true));
      expect(pastille().isLabelVisible, isTrue);
      await tester.tap(find.text('Message'));
      expect(appels.last, 'message');
    });
  });
}
