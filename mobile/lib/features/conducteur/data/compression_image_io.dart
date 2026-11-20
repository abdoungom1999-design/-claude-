import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Compression en Dart (APK Android, tests) : décodage, orientation,
/// redimensionnement et JPEG, dans un isolat pour ne pas geler l'écran.
/// `null` si l'image ne peut pas être lue ou ne descend pas sous [tailleMax].
Future<Uint8List?> compresser(
  Uint8List octets, {
  required List<int> cotes,
  required List<double> qualites,
  required int tailleMax,
}) =>
    Isolate.run(() => compresserSansIsolat(octets, cotes: cotes, qualites: qualites, tailleMax: tailleMax));

/// Même travail, dans le fil courant (utilisé par l'isolat ci-dessus).
Uint8List? compresserSansIsolat(
  Uint8List octets, {
  required List<int> cotes,
  required List<double> qualites,
  required int tailleMax,
}) {
  img.Image? image;
  try {
    image = img.decodeImage(octets);
  } on Object {
    image = null;
  }
  if (image == null) return null;
  // Photo prise téléphone en portrait : l'information d'orientation est appliquée.
  final oriente = img.bakeOrientation(image);
  for (final cote in cotes) {
    final grand = oriente.width >= oriente.height ? oriente.width : oriente.height;
    final reduite = grand <= cote
        ? oriente
        : img.copyResize(
            oriente,
            width: oriente.width >= oriente.height ? cote : null,
            height: oriente.height > oriente.width ? cote : null,
            interpolation: img.Interpolation.average,
          );
    // Une image avec transparence (PNG) est posée sur du blanc avant le JPEG.
    final opaque = reduite.hasAlpha ? (img.Image(width: reduite.width, height: reduite.height)..clear(img.ColorRgb8(255, 255, 255))) : null;
    if (opaque != null) img.compositeImage(opaque, reduite);
    final aEncoder = opaque ?? reduite;
    for (final qualite in qualites) {
      final jpeg = img.encodeJpg(aEncoder, quality: (qualite * 100).round());
      if (jpeg.lengthInBytes < tailleMax) return jpeg;
    }
  }
  return null;
}
