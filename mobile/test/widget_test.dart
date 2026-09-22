import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/app.dart';

void main() {
  testWidgets('affiche le choix binaire Passager / Livraison Colis', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SprintApp());

    expect(find.text('Passager'), findsOneWidget);
    expect(find.text('Livraison Colis'), findsOneWidget);
  });
}
