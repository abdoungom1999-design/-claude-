import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sprint/features/conducteur/data/compression_image.dart';
import 'package:sprint/features/conducteur/data/piece_kyc.dart';

/// Photo « réaliste » : dégradés, formes et un léger grain (comme un vrai cliché).
img.Image _photo(int largeur, int hauteur, {int grain = 18, int graine = 1}) {
  final hasard = Random(graine);
  final image = img.Image(width: largeur, height: hauteur);
  for (var y = 0; y < hauteur; y++) {
    for (var x = 0; x < largeur; x++) {
      final r = (x * 255 ~/ largeur + hasard.nextInt(grain)).clamp(0, 255);
      final g = (y * 255 ~/ hauteur + hasard.nextInt(grain)).clamp(0, 255);
      final b = (((x ~/ 40 + y ~/ 40) % 2) * 120 + hasard.nextInt(grain)).clamp(0, 255);
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

img.Image _decoder(Uint8List octets) => img.decodeJpg(octets)!;

void main() {
  test('grande photo (4032 x 3024, plusieurs Mo) : JPEG de moins de 150 Ko, 1024 px de côté au plus, en moins de 3 secondes', () async {
    final source = Uint8List.fromList(img.encodeJpg(_photo(4032, 3024), quality: 95));
    expect(source.lengthInBytes, greaterThan(1024 * 1024), reason: 'la photo de départ doit être lourde');

    final chrono = Stopwatch()..start();
    final resultat = await compresserImageKyc(source);
    chrono.stop();

    expect(resultat.lengthInBytes, lessThan(150 * 1024));
    expect(detecterTypePiece(resultat), TypePiece.jpeg);
    final lue = _decoder(resultat);
    expect(max(lue.width, lue.height), lessThanOrEqualTo(1024));
    expect(lue.width, greaterThan(lue.height), reason: 'paysage reste paysage');
    expect(chrono.elapsed, lessThan(const Duration(seconds: 3)), reason: 'compression en ${chrono.elapsedMilliseconds} ms');
  });

  test('photo en portrait : reste en portrait (1024 px de haut au plus)', () async {
    final source = Uint8List.fromList(img.encodeJpg(_photo(1500, 2000, graine: 2), quality: 90));
    final lue = _decoder(await compresserImageKyc(source));
    expect(lue.height, greaterThan(lue.width));
    expect(lue.height, lessThanOrEqualTo(1024));
  });

  test('orientation de l\'appareil photo (EXIF) appliquée : une photo « tournée » ressort droite', () async {
    final photo = _photo(1200, 800, graine: 3);
    photo.exif.imageIfd.orientation = 6; // téléphone tenu en portrait : rotation de 90°
    final source = Uint8List.fromList(img.encodeJpg(photo, quality: 90));
    final lue = _decoder(await compresserImageKyc(source));
    expect(lue.height, greaterThan(lue.width), reason: 'la rotation demandée par la photo est appliquée');
  });

  test('PNG avec transparence : devient un JPEG opaque', () async {
    final png = img.Image(width: 600, height: 400, numChannels: 4)..clear(img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(png, x1: 100, y1: 100, x2: 300, y2: 300, color: img.ColorRgba8(34, 224, 122, 255));
    final resultat = await compresserImageKyc(Uint8List.fromList(img.encodePng(png)));
    expect(detecterTypePiece(resultat), TypePiece.jpeg);
    final lue = _decoder(resultat);
    final coin = lue.getPixel(5, 5);
    expect(coin.r, greaterThan(240), reason: 'fond transparent posé sur du blanc, pas du noir');
  });

  test('cas le plus dur (bruit pur, 3000 x 2000) : la taille reste sous 150 Ko grâce aux côtés plus petits', () async {
    final hasard = Random(9);
    final bruit = img.Image(width: 3000, height: 2000);
    for (final p in bruit) {
      p
        ..r = hasard.nextInt(256)
        ..g = hasard.nextInt(256)
        ..b = hasard.nextInt(256);
    }
    final resultat = await compresserImageKyc(Uint8List.fromList(img.encodeJpg(bruit, quality: 90)));
    expect(resultat.lengthInBytes, lessThan(150 * 1024));
  });

  test('petite photo déjà légère : recompressée en JPEG, pas agrandie', () async {
    final source = Uint8List.fromList(img.encodePng(_photo(300, 200, graine: 4)));
    final lue = _decoder(await compresserImageKyc(source));
    expect([lue.width, lue.height], [300, 200]);
  });

  test('fichier illisible ou vide : refus clair (jamais un envoi non compressé)', () async {
    for (final illisible in [Uint8List(0), Uint8List.fromList(List.filled(500, 7)), Uint8List.fromList('%PDF-1.4'.codeUnits)]) {
      await expectLater(compresserImageKyc(illisible), throwsA(isA<CompressionImpossibleException>()));
    }
  });

  test('réglages : 150 Ko strictement, 1024 px, qualité 0,65 en premier', () {
    expect(tailleMaxImageKyc, 150 * 1024);
    expect(coteMaxImageKyc, 1024);
    expect(qualitesImageKyc.first, 0.65);
    expect(cotesImageKyc.first, 1024);
    // Une photo compressée passe toujours par l'envoi de secours (180 Ko) : deux photos tiennent sous la limite Firestore.
    expect(tailleMaxImageKyc, lessThan(limiteOctetsRepliBase64));
    expect(repliBase64Possible(TypePiece.jpeg, tailleMaxImageKyc - 1), isTrue);
  });
}
