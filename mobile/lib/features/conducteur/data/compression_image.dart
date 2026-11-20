import 'dart:typed_data';

import 'compression_image_io.dart' if (dart.library.js_interop) 'compression_image_web.dart' as plateforme;

/// Plafond d'une photo du dossier chauffeur après compression : STRICTEMENT
/// moins de 150 Ko. Elle part en 1 à 2 secondes sur 4G, et même l'envoi de
/// secours (image encodée dans le profil, voir `limiteOctetsRepliBase64`) passe
/// à coup sûr sous la limite d'évaluation des règles Firestore.
const int tailleMaxImageKyc = 150 * 1024;

/// Plus grand côté de la photo envoyée (en pixels).
const int coteMaxImageKyc = 1024;

/// Qualités JPEG essayées dans l'ordre, puis côtés plus petits si nécessaire :
/// la première combinaison sous [tailleMaxImageKyc] est gardée.
const List<double> qualitesImageKyc = [0.65, 0.55, 0.45, 0.35];
const List<int> cotesImageKyc = [coteMaxImageKyc, 800, 640, 480];

/// La photo n'a pas pu être lue (format que l'appareil ne sait pas décoder,
/// fichier abîmé) ou ne descend pas sous [tailleMaxImageKyc].
class CompressionImpossibleException implements Exception {
  const CompressionImpossibleException();
}

/// Réduit SYSTÉMATIQUEMENT une photo en JPEG : au plus [coteMaxImageKyc] pixels
/// de côté, qualité 0,65 (puis moins si besoin), strictement moins de
/// [tailleMaxImageKyc] octets. Ne se fie pas aux réglages du sélecteur de photos
/// (souvent ignorés par Safari) :
/// - sur le site (iPhone compris) : le navigateur décode l'image (HEIC compris
///   sur iPhone), la redessine dans un canvas et l'encode en JPEG ;
/// - sur l'APK Android : décodage, redimensionnement et encodage en Dart, hors
///   du fil de l'interface (pas de gel de l'écran).
/// L'orientation de la photo (téléphone tenu en portrait) est respectée.
Future<Uint8List> compresserImageKyc(Uint8List octets) async {
  final resultat = await plateforme.compresser(
    octets,
    cotes: cotesImageKyc,
    qualites: qualitesImageKyc,
    tailleMax: tailleMaxImageKyc,
  );
  if (resultat == null || resultat.lengthInBytes >= tailleMaxImageKyc) {
    throw const CompressionImpossibleException();
  }
  return resultat;
}
