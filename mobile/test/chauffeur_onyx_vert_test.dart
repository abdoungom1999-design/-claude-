import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/core/widgets/app_card.dart';
import 'package:sprint/core/widgets/onyx_vert.dart';
import 'package:sprint/features/conducteur/presentation/widgets/bouton_en_ligne_circulaire.dart';
import 'package:sprint/features/conducteur/presentation/widgets/conducteur_bottom_nav.dart';

void main() {
  testWidgets('Chauffeur : barre du bas Onyx & Vert (fond Onyx, icônes grises, onglet actif vert)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(bottomNavigationBar: ConducteurBottomNav(indexSelectionne: 0, onSelection: (_) {})),
    ));
    final barre = tester.widget<BottomAppBar>(find.byType(BottomAppBar));
    expect(barre.color, AppColors.fondBarre);
    Color? couleur(String libelle) => tester.widget<Text>(find.text(libelle)).style?.color;
    expect(couleur('Accueil'), AppColors.vert);
    for (final inactif in ['Messages', 'Gains', 'Évaluations', 'Compte']) {
      expect(couleur(inactif), AppColors.texteDiscret);
    }
  });

  testWidgets('Chauffeur : l\'onglet touché devient l\'onglet actif et prévient la page', (tester) async {
    var choisi = -1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(bottomNavigationBar: ConducteurBottomNav(indexSelectionne: 0, onSelection: (i) => choisi = i)),
    ));
    await tester.tap(find.text('Gains'));
    expect(choisi, 2);
  });

  testWidgets('Chauffeur : bouton GO vert à texte Onyx, « EN LIGNE » une fois connecté', (tester) async {
    Future<void> afficher(bool enLigne) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BoutonEnLigneCirculaire(enLigne: enLigne, onTap: () {}))));
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> verifier(String libelle) async {
      final bouton = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      expect((bouton.decoration! as BoxDecoration).gradient, AppColors.degradeAction);
      expect(tester.widget<Text>(find.text(libelle)).style?.color, AppColors.onyx);
    }

    await afficher(false);
    await verifier('GO');
    await afficher(true);
    await verifier('EN LIGNE');
  });

  testWidgets('Chauffeur : un onglet enveloppé dans EcranOnyxVert prend la charte (fond Onyx, cartes verre)', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: EcranOnyxVert(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: AppCard(child: Text('Gains', style: styleTitreEcran)),
        ),
      ),
    ));
    expect(find.byType(ThemeOnyxVert), findsOneWidget);
    expect(find.byType(FondOnyxVert), findsOneWidget);
    // AppCard devient une carte verre dans la charte.
    expect(find.byType(CarteVerre), findsOneWidget);
    expect(tester.widget<Text>(find.text('Gains')).style?.color, AppColors.texte);
  });
}
