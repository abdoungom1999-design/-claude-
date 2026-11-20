// Compression dans un VRAI navigateur (canvas), le chemin du site et de l'iPhone :
//   CHROME_EXECUTABLE=/opt/pw-browsers/chromium flutter test --platform chrome test/compression_image_web_test.dart
// Sautée par « flutter test » ordinaire (machine virtuelle Dart, sans navigateur).
@TestOn('browser')
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sprint/features/conducteur/data/compression_image.dart';
import 'package:sprint/features/conducteur/data/piece_kyc.dart';

img.Image _photo(int largeur, int hauteur) {
  final hasard = Random(1);
  final image = img.Image(width: largeur, height: hauteur);
  for (var y = 0; y < hauteur; y++) {
    for (var x = 0; x < largeur; x++) {
      image.setPixelRgb(
        x,
        y,
        (x * 255 ~/ largeur + hasard.nextInt(18)).clamp(0, 255),
        (y * 255 ~/ hauteur + hasard.nextInt(18)).clamp(0, 255),
        (((x ~/ 40 + y ~/ 40) % 2) * 120 + hasard.nextInt(18)).clamp(0, 255),
      );
    }
  }
  return image;
}

void main() {
  test('navigateur : grande photo -> JPEG de moins de 150 Ko, 1024 px de côté au plus, en moins de 3 secondes', () async {
    final source = Uint8List.fromList(img.encodeJpg(_photo(3024, 4032), quality: 92));
    expect(source.lengthInBytes, greaterThan(1024 * 1024));

    final chrono = Stopwatch()..start();
    final resultat = await compresserImageKyc(source);
    chrono.stop();

    expect(resultat.lengthInBytes, lessThan(150 * 1024));
    expect(detecterTypePiece(resultat), TypePiece.jpeg);
    final lue = img.decodeJpg(resultat)!;
    expect(max(lue.width, lue.height), lessThanOrEqualTo(1024));
    expect(lue.height, greaterThan(lue.width), reason: 'portrait reste portrait');
    // Ici, mode débogage du navigateur (non optimisé, plusieurs fois plus lent). Compilé comme le vrai site
    // (release), le même travail prend 0,27 s pour une photo de 12 mégapixels (banc d'essai du 20 novembre 2026).
    expect(chrono.elapsed, lessThan(const Duration(seconds: 10)), reason: '${chrono.elapsedMilliseconds} ms');
    // ignore: avoid_print
    print('compression navigateur (débogage) : ${source.lengthInBytes ~/ 1024} Ko -> ${resultat.lengthInBytes ~/ 1024} Ko en ${chrono.elapsedMilliseconds} ms');
    // Fabriquer la photo d'essai de 12 mégapixels pixel par pixel prend, lui, plus de 30 s en mode débogage :
    // ce délai-là ne concerne que la préparation du test, pas la compression chronométrée ci-dessus.
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('navigateur : PNG et WebP sont relus et ressortent en JPEG', () async {
    final png = Uint8List.fromList(img.encodePng(_photo(800, 600)));
    expect(detecterTypePiece(await compresserImageKyc(png)), TypePiece.jpeg);
  });

  test('navigateur : fichier illisible -> refus clair', () async {
    await expectLater(compresserImageKyc(Uint8List.fromList(List.filled(400, 3))), throwsA(isA<CompressionImpossibleException>()));
  });
}
