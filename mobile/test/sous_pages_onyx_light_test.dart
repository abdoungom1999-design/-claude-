import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/widgets/onyx_light.dart';
import 'package:sprint/features/activite/presentation/receipts_page.dart';
import 'package:sprint/features/compte/presentation/a_propos_page.dart';
import 'package:sprint/features/compte/presentation/aide_support_page.dart';
import 'package:sprint/features/compte/presentation/conditions_utilisation_page.dart';
import 'package:sprint/features/compte/presentation/favoris_page.dart';
import 'package:sprint/features/compte/presentation/nous_contacter_page.dart';
import 'package:sprint/features/compte/presentation/notifications_page.dart';
import 'package:sprint/features/compte/presentation/politique_confidentialite_page.dart';
import 'package:sprint/features/compte/presentation/preferences_page.dart';

/// Les sous-pages ouvertes par `Navigator.push` ne reçoivent pas le thème de
/// l'écran qui les ouvre : chacune doit s'habiller elle-même (SousPageOnyx).
void main() {
  final pages = <String, Widget>{
    'Aide & Support': const AideSupportPage(),
    'À propos': const AProposPage(),
    'Conditions d\'utilisation': const ConditionsUtilisationPage(),
    'Politique de confidentialité': const PolitiqueConfidentialitePage(),
    'Favoris': const FavorisPage(),
    'Nous contacter': const NousContacterPage(),
    'Notifications': const NotificationsPage(),
    'Préférences': const PreferencesPage(),
    'Reçus': const ReceiptsPage(),
  };

  for (final MapEntry(key: nom, value: page) in pages.entries) {
    testWidgets('$nom : charte Onyx & Light, fond transparent, aucun débordement à 320 px', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pump();

      expect(find.byType(SousPageOnyx), findsOneWidget);
      expect(find.byType(FondOnyxLight), findsOneWidget);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, isNull, reason: 'le fond vient du thème (transparent), pas de la page');
      expect(Theme.of(tester.element(find.byType(Scaffold).first)).scaffoldBackgroundColor, Colors.transparent);
      expect(tester.takeException(), isNull);
    });
  }
}
