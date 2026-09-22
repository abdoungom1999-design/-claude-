import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/app.dart';

void main() {
  testWidgets('affiche l\'écran Welcome avec ses entrées de connexion', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SprintApp());

    expect(find.text('Sprint'), findsOneWidget);
    expect(find.text('Continuer avec mon numéro'), findsOneWidget);
    expect(find.text('Continuer avec mon email'), findsOneWidget);
    expect(find.text('Continuer avec Apple'), findsOneWidget);
  });
}
