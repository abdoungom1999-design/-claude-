import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/core/widgets/onyx_light.dart';
import 'package:sprint/features/compte/presentation/compte_tab_page.dart';

void main() {
  testWidgets('Compte : charte Onyx & Light (fond clair, cartes verre, solde Onyx, bouton Recharger orange)', (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: CompteTabPage(demo: true, profil: Stream.value(null))));
    await tester.pump();

    // Écran enveloppé dans la charte, sur fond clair.
    expect(find.byType(ThemeOnyxLight), findsOneWidget);
    expect(find.byType(FondOnyxLight), findsOneWidget);
    expect(find.byType(CarteVerre), findsWidgets);

    // Solde en Onyx.
    final solde = tester.widget<Text>(find.byKey(const ValueKey('solde-portefeuille')));
    expect(solde.style?.color, AppColors.onyx);

    // Bouton Recharger orange Sprint.
    final bouton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Recharger'));
    expect(bouton.style?.backgroundColor?.resolve({}), AppColors.orange);
  });
}
