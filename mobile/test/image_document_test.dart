import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/widgets/image_document.dart';

// PNG 1x1 transparent.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

Widget _app(String? source) => MaterialApp(
      home: ImageDocument(source: source, placeholder: const Text('vide')),
    );

void main() {
  testWidgets('source absente : affiche le placeholder', (tester) async {
    await tester.pumpWidget(_app(null));
    expect(find.text('vide'), findsOneWidget);
  });

  testWidgets('data URI Base64 (anciens dossiers) : décodée en mémoire', (tester) async {
    await tester.pumpWidget(_app('data:image/png;base64,$_pngBase64'));
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
  });

  testWidgets('URL Firebase Storage : chargée via le réseau', (tester) async {
    await tester.pumpWidget(_app('https://firebasestorage.googleapis.com/v0/b/x/o/a.jpg'));
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
  });
}
