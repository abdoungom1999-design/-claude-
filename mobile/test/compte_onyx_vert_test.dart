import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/core/widgets/onyx_vert.dart';
import 'package:sprint/features/compte/presentation/compte_tab_page.dart';

void main() {
  testWidgets('Compte : charte Onyx & Vert (fond Onyx, cartes verre, solde en clair, bouton Recharger vert à texte Onyx)', (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: CompteTabPage(demo: true, profil: Stream.value(null))));
    await tester.pump();

    // Écran enveloppé dans la charte, sur fond Onyx.
    expect(find.byType(ThemeOnyxVert), findsOneWidget);
    expect(find.byType(FondOnyxVert), findsOneWidget);
    expect(find.byType(CarteVerre), findsWidgets);

    // Solde en texte clair.
    final solde = tester.widget<Text>(find.byKey(const ValueKey('solde-portefeuille')));
    expect(solde.style?.color, AppColors.texte);

    // Bouton Recharger : vert d'action, texte Onyx.
    final bouton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Recharger'));
    expect(bouton.style?.backgroundColor?.resolve({}), AppColors.vert);
    expect(bouton.style?.foregroundColor?.resolve({}), AppColors.onyx);
  });
}
