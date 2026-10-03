import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/models/statut_compte.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/core/widgets/onyx_light.dart';
import 'package:sprint/features/compte/presentation/centre_aide_page.dart';
import 'package:sprint/features/conducteur/presentation/conducteur_compte_bloque_page.dart';
import 'package:sprint/features/conducteur/presentation/conducteur_en_attente_page.dart';
import 'package:sprint/features/conducteur/presentation/conducteur_kyc_page.dart';
import 'package:sprint/features/conducteur/presentation/validation_pending_page.dart';

Future<void> _ecran(WidgetTester tester, Widget page, {Size taille = const Size(390, 844)}) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump();
}

Widget _kyc(Map<String, dynamic> documents, {VoidCallback? onSoumis}) => ConducteurKYCPage(
      onDossierSoumis: onSoumis ?? () {},
      onDeconnexion: () {},
      fluxProfil: Stream.value({'documents': documents}),
    );

void main() {
  testWidgets('Dossier en attente : charte Onyx & Light, trois étapes, déconnexion', (tester) async {
    var deconnecte = false;
    await _ecran(tester, ConducteurEnAttentePage(onDeconnexion: () => deconnecte = true));

    expect(find.byType(EcranOnyxLight), findsOneWidget);
    expect(find.byType(CarteVerre), findsOneWidget);
    expect(find.text('Dossier en cours de vérification'), findsOneWidget);
    for (final etape in ['Dossier reçu', 'Vérification', 'Compte activé']) {
      expect(find.text(etape), findsOneWidget);
    }
    await tester.tap(find.text('Se déconnecter'));
    expect(deconnecte, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Écrans d\'attente : aucun débordement sur un petit téléphone (320 x 568)', (tester) async {
    const petit = Size(320, 568);
    await _ecran(tester, ConducteurEnAttentePage(onDeconnexion: () {}), taille: petit);
    expect(tester.takeException(), isNull);
    await _ecran(tester, const ValidationPendingPage(), taille: petit);
    expect(tester.takeException(), isNull);
    await _ecran(tester, const ConducteurCompteBloquePage(statutCompte: StatutCompte.banni), taille: petit);
    expect(tester.takeException(), isNull);
    await _ecran(tester, _kyc({}), taille: petit);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Compte désactivé : rouge d\'alerte ; compte suspendu : médaillon Onyx à icône orange', (tester) async {
    await _ecran(tester, const ConducteurCompteBloquePage(statutCompte: StatutCompte.banni));
    expect(find.text('Compte désactivé'), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(Icons.block_rounded)).color, Colors.red.shade700);

    await _ecran(tester, const ConducteurCompteBloquePage(statutCompte: StatutCompte.suspendu));
    expect(find.text('Compte suspendu'), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(Icons.pause_circle_outline_rounded)).color, AppColors.orange);
  });

  testWidgets('Dossier KYC : bouton inactif tant que les 3 documents ne sont pas envoyés', (tester) async {
    await _ecran(tester, _kyc({'permis': 'x'}));

    expect(find.text('1 document sur 3 envoyé'), findsOneWidget);
    expect(find.text('Envoyé'), findsOneWidget);
    expect(find.text('Ajouter'), findsNWidgets(2));
    final bouton = find.widgetWithText(ElevatedButton, 'Soumettre mon dossier');
    expect(tester.widget<ElevatedButton>(bouton).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dossier KYC : les 3 documents envoyés activent la soumission', (tester) async {
    var soumis = false;
    await _ecran(tester, _kyc({'permis': 'x', 'carteGrise': 'x', 'attestationVtc': 'x'}, onSoumis: () => soumis = true));

    expect(find.text('3 documents sur 3 envoyés'), findsOneWidget);
    await tester.tap(find.text('Soumettre mon dossier'));
    expect(soumis, isTrue);
  });

  testWidgets("Centre d'aide : charte Onyx & Light, accordéon, aucun débordement à 320 px", (tester) async {
    await _ecran(tester, const CentreAidePage(), taille: const Size(320, 640));

    expect(find.byType(EcranOnyxLight), findsOneWidget);
    expect(find.text('Questions fréquentes'), findsOneWidget);
    expect(find.textContaining('Trois moyens de paiement'), findsNothing);
    await tester.tap(find.text('Comment payer ma course ?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Trois moyens de paiement'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('Contacter le support'), 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Contacter le support'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contacter le support'));
    await tester.pumpAndSettle();
    expect(find.text('Message envoyé'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
