import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/widgets/onyx_vert.dart';
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
    testWidgets('$nom : charte Onyx & Vert, fond transparent, aucun débordement à 320 px', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pump();

      expect(find.byType(SousPageOnyx), findsOneWidget);
      expect(find.byType(FondOnyxVert), findsOneWidget);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, isNull, reason: 'le fond vient du thème (transparent), pas de la page');
      expect(Theme.of(tester.element(find.byType(Scaffold).first)).scaffoldBackgroundColor, Colors.transparent);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Conditions d\'utilisation : le Conducteur s\'engage sur les autorisations légales, l\'assurance, sa photo et sa carte d\'identité', (tester) async {
    tester.view.physicalSize = const Size(390, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ConditionsUtilisationPage()));
    await tester.pump();

    expect(
      find.textContaining(
        'Le Conducteur s\'engage à détenir les autorisations légales et une assurance valide requises pour '
        'l\'exercice de son activité au Sénégal, et à fournir une photo récente de lui-même ainsi que sa '
        'carte d\'identité.',
      ),
      findsOneWidget,
    );
    // Publication 146 : les deux pièces demandées sont la photo et la carte d'identité ; ni le permis ni la
    // carte grise ne sont plus cités.
    expect(find.textContaining('permis de conduire'), findsNothing);
    expect(find.textContaining('carte grise'), findsNothing);
  });

  testWidgets('Aide & Support : plus de faux fil « Mes échanges » (rien n\'y était envoyé à personne)', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AideSupportPage()));
    await tester.pump();

    expect(find.text('Mes échanges'), findsNothing);
    expect(find.byIcon(Icons.forum_outlined), findsNothing);
    // Plus de numéro de téléphone : « Nous contacter » porte l'icône courrier.
    expect(find.byIcon(Icons.call_outlined), findsNothing);
    expect(find.byIcon(Icons.mail_outline_rounded), findsOneWidget);
    for (final reste in ['Centre d\'aide', 'Nous contacter', 'À propos de Sprint']) {
      expect(find.text(reste), findsOneWidget, reason: reste);
    }
  });

  testWidgets('Nous contacter : une seule adresse officielle, aucun numéro de téléphone fictif', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: NousContacterPage()));
    await tester.pump();

    expect(find.text('contact@sprintvtc.sn'), findsOneWidget);
    expect(find.textContaining('+221 33'), findsNothing);
    expect(find.byIcon(Icons.phone_outlined), findsNothing);
  });

  testWidgets('Préférences : plus de choix de thème, l\'app est uniquement en mode sombre', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PreferencesPage()));
    await tester.pump();

    for (final disparu in ['Thème', 'Clair', 'Sombre', 'Système']) {
      expect(find.text(disparu), findsNothing, reason: disparu);
    }
    for (final reste in ['Localisation', 'Unité de distance', 'Format d\'heure', 'Devise', 'Enregistrer']) {
      expect(find.text(reste), findsOneWidget, reason: reste);
    }
  });
}
