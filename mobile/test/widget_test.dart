import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spid/app.dart';

void main() {
  testWidgets('affiche le choix binaire Passager / Livraison Colis', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SpidApp());

    expect(find.text('Passager'), findsOneWidget);
    expect(find.text('Livraison Colis'), findsOneWidget);
  });
}
