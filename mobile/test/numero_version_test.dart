import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/widgets/auth_scaffold.dart';
import 'package:sprint/core/widgets/numero_version.dart';
import 'package:sprint/features/conducteur/presentation/conducteur_kyc_page.dart';

void main() {
  testWidgets('numéro de publication connu : « v146 », discret', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NumeroVersion(numero: '146'))));
    expect(find.text('v146'), findsOneWidget);
  });

  testWidgets("numéro inconnu (développement, tests) : rien n'est affiché", (tester) async {
    for (final vide in ['', '  ']) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: NumeroVersion(numero: vide))));
      expect(find.byKey(const ValueKey('numero-version')), findsNothing);
    }
  });

  testWidgets('les écrans de connexion et le dossier chauffeur portent le numéro de version', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: AuthScaffold(icon: Icons.person, title: 'Connexion', subtitle: 'Bonjour', form: SizedBox(height: 20)),
    ));
    expect(find.byType(NumeroVersion), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: ConducteurKYCPage(onDossierSoumis: () {}, onDeconnexion: () {}, fluxProfil: Stream.value(const {'documents': <String, dynamic>{}})),
    ));
    await tester.pump();
    expect(find.byType(NumeroVersion), findsOneWidget);
  });
}
