import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/admin/presentation/widgets/visionneuse_document.dart';

// PNG 1x1 transparent.
const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

void main() {
  testWidgets('Visionneuse : zoom, rotation (qui réinitialise le zoom) puis fermeture', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => ouvrirVisionneuseDocument(context, titre: 'Permis de conduire', source: _png),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('Permis de conduire'), findsOneWidget);

    final controleur = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!;

    await tester.tap(find.byTooltip('Zoomer'));
    await tester.pump();
    expect(controleur.value.getMaxScaleOnAxis(), closeTo(1.5, 0.001));

    await tester.tap(find.byTooltip('Pivoter'));
    await tester.pump();
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 1);
    expect(controleur.value.getMaxScaleOnAxis(), closeTo(1, 0.001));

    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    expect(find.text('Permis de conduire'), findsNothing);
  });
}
