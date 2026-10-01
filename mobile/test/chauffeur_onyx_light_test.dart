import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/core/widgets/app_card.dart';
import 'package:sprint/core/widgets/onyx_light.dart';
import 'package:sprint/features/conducteur/presentation/widgets/bouton_en_ligne_circulaire.dart';
import 'package:sprint/features/conducteur/presentation/widgets/conducteur_bottom_nav.dart';

void main() {
  testWidgets('Chauffeur : barre du bas Onyx & Light (fond clair, icônes Onyx, onglet actif orange)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(bottomNavigationBar: ConducteurBottomNav(indexSelectionne: 0, onSelection: (_) {})),
    ));
    final barre = tester.widget<BottomAppBar>(find.byType(BottomAppBar));
    expect(barre.color, AppColors.fondBarre);
    Color? couleur(String libelle) => tester.widget<Text>(find.text(libelle)).style?.color;
    expect(couleur('Accueil'), AppColors.orange);
    for (final inactif in ['Messages', 'Gains', 'Évaluations', 'Compte']) {
      expect(couleur(inactif), AppColors.onyx);
    }
  });

  testWidgets('Chauffeur : bouton GO Onyx hors ligne, orange en ligne', (tester) async {
    Future<Color> premiereCouleur(bool enLigne) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BoutonEnLigneCirculaire(enLigne: enLigne, onTap: () {}))));
      await tester.pump(const Duration(milliseconds: 500));
      final bouton = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      return ((bouton.decoration! as BoxDecoration).gradient! as LinearGradient).colors.last;
    }

    expect(await premiereCouleur(false), AppColors.onyx);
    expect(await premiereCouleur(true), AppColors.orangeDark);
  });

  testWidgets('Chauffeur : un onglet enveloppé dans EcranOnyxLight prend la charte (fond clair, cartes verre)', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: EcranOnyxLight(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: AppCard(child: Text('Gains', style: styleTitreEcran)),
        ),
      ),
    ));
    expect(find.byType(ThemeOnyxLight), findsOneWidget);
    expect(find.byType(FondOnyxLight), findsOneWidget);
    // AppCard devient une carte verre dans la charte.
    expect(find.byType(CarteVerre), findsOneWidget);
    expect(tester.widget<Text>(find.text('Gains')).style?.color, AppColors.onyx);
  });
}
