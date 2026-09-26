import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/widgets/trip_map.dart';
import 'package:sprint/features/conducteur/presentation/tabs/conducteur_accueil_tab.dart';

/// Vérifie que les deux écrans branchés sur [AdaptiveMap] (préparation
/// Google Maps, voir GOOGLE_MAPS_SETUP.md) construisent leur arbre de
/// widgets sans exception tant qu'aucune clé API réelle n'est
/// configurée — c'est-à-dire tant qu'ils affichent la branche
/// OpenStreetMap/`flutter_map`, la seule exerçable dans cet
/// environnement de test (pas de plateforme native pour le rendu
/// `GoogleMap`).
void main() {
  testWidgets('TripMap construit sans exception (branche OpenStreetMap)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TripMap())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TripMap), findsOneWidget);
  });

  testWidgets('ConducteurAccueilTab construit sans exception (carte + HUD)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConducteurAccueilTab(
          enLigne: true,
          onBasculerStatut: (_) {},
          gainsJourFcfa: 5000,
          onSimulerCourse: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ConducteurAccueilTab), findsOneWidget);
  });
}
