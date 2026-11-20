import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Compression dans le navigateur (site, iPhone compris) : l'image est décodée
/// par le navigateur (qui sait lire le HEIC de l'iPhone et applique
/// l'orientation de la photo), redessinée dans un canvas à la bonne taille, puis
/// encodée en JPEG. `null` si l'image ne peut pas être lue ou ne descend pas
/// sous [tailleMax].
Future<Uint8List?> compresser(
  Uint8List octets, {
  required List<int> cotes,
  required List<double> qualites,
  required int tailleMax,
}) async {
  final adresse = web.URL.createObjectURL(web.Blob([octets.toJS].toJS));
  try {
    final image = web.HTMLImageElement()..src = adresse;
    try {
      await image.decode().toDart;
    } on Object {
      return null; // Format que ce navigateur ne sait pas lire.
    }
    final largeur = image.naturalWidth;
    final hauteur = image.naturalHeight;
    if (largeur <= 0 || hauteur <= 0) return null;
    for (final cote in cotes) {
      final echelle = math.min(1.0, cote / math.max(largeur, hauteur));
      final canvas = web.HTMLCanvasElement()
        ..width = math.max(1, (largeur * echelle).round())
        ..height = math.max(1, (hauteur * echelle).round());
      final contexte = canvas.getContext('2d');
      if (contexte == null) return null;
      final dessin = contexte as web.CanvasRenderingContext2D;
      // Fond blanc : une image avec transparence (PNG) ne devient pas noire en JPEG.
      dessin.fillStyle = '#FFFFFF'.toJS;
      dessin.fillRect(0, 0, canvas.width, canvas.height);
      dessin.drawImage(image, 0, 0, canvas.width, canvas.height);
      for (final qualite in qualites) {
        final blob = await _versBlob(canvas, qualite);
        if (blob == null) continue;
        final tampon = await blob.arrayBuffer().toDart;
        final jpeg = tampon.toDart.asUint8List();
        if (jpeg.lengthInBytes < tailleMax) return jpeg;
      }
    }
    return null;
  } finally {
    web.URL.revokeObjectURL(adresse);
  }
}

Future<web.Blob?> _versBlob(web.HTMLCanvasElement canvas, double qualite) {
  final termine = Completer<web.Blob?>();
  canvas.toBlob(
    ((web.Blob? blob) {
      if (!termine.isCompleted) termine.complete(blob);
    }).toJS,
    'image/jpeg',
    qualite.toJS,
  );
  return termine.future;
}
