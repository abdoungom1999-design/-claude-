import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';

/// Les pièces que l'app accepte, reconnues d'après leur CONTENU (les premiers
/// octets) et non d'après leur nom ou le type annoncé par le téléphone : sur
/// iPhone, une photo peut porter un nom ou un type qui ne correspond pas à ce
/// qu'elle contient, et Firebase Storage refuse un type mal annoncé.
enum TypePiece {
  jpeg('image/jpeg', 'jpg'),
  png('image/png', 'png'),
  webp('image/webp', 'webp'),
  pdf('application/pdf', 'pdf');

  const TypePiece(this.contentType, this.extension);

  /// Type annoncé à Firebase Storage (il doit être exact : les règles le contrôlent).
  final String contentType;
  final String extension;

  bool get estImage => this != pdf;
}

bool _commencePar(Uint8List o, List<int> motif, [int debut = 0]) {
  if (o.length < debut + motif.length) return false;
  for (var i = 0; i < motif.length; i++) {
    if (o[debut + i] != motif[i]) return false;
  }
  return true;
}

/// Type réel d'une pièce, ou `null` si ce n'est ni un JPEG, ni un PNG, ni un
/// WebP, ni un PDF.
TypePiece? detecterTypePiece(Uint8List octets) {
  if (_commencePar(octets, [0xFF, 0xD8, 0xFF])) return TypePiece.jpeg;
  if (_commencePar(octets, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return TypePiece.png;
  // WebP : « RIFF » + taille + « WEBP ».
  if (_commencePar(octets, [0x52, 0x49, 0x46, 0x46]) && _commencePar(octets, [0x57, 0x45, 0x42, 0x50], 8)) {
    return TypePiece.webp;
  }
  // PDF : « %PDF ».
  if (_commencePar(octets, [0x25, 0x50, 0x44, 0x46])) return TypePiece.pdf;
  return null;
}

/// Photo au format HEIC/HEIF (iPhone) ou AVIF : reconnue pour donner un message
/// clair, mais jamais envoyée telle quelle (l'Admin ne pourrait pas l'ouvrir).
/// En pratique, le sélecteur de photos du téléphone convertit déjà en JPEG ;
/// ce cas ne se produit que si un fichier brut est choisi.
bool estPieceHeic(Uint8List octets) {
  if (!_commencePar(octets, [0x66, 0x74, 0x79, 0x70], 4) || octets.length < 12) return false;
  final marque = String.fromCharCodes(octets.sublist(8, 12));
  return const ['heic', 'heix', 'hevc', 'hevx', 'heim', 'heis', 'mif1', 'msf1', 'avif'].contains(marque);
}

/// Ce que les règles Firestore savent évaluer : environ 1 000 000 de caractères
/// d'images encodées (Base64) AU TOTAL dans `users/{uid}.documents`, mesuré sur
/// l'émulateur (une pièce : 998 000 ; deux : 524 000 chacune ; trois : 348 000 ;
/// quatre : 260 000). Au-delà, Firestore répond « permission-denied » par
/// « maximum memory usage of 1000 » — sans rapport avec les droits du chauffeur —
/// et toute écriture suivante sur ce profil est refusée aussi.
const int capaciteReglesBase64Caracteres = 1000000;

/// Plafond d'une image envoyée en REPLI (Storage indisponible) : 180 Ko, soit
/// environ 246 000 caractères encodés. Quatre pièces tiennent ainsi sous
/// [capaciteReglesBase64Caracteres] ; au-delà, le repli ferait échouer la
/// deuxième pièce, et l'échec réel (Storage) serait masqué.
const int limiteOctetsRepliBase64 = 180 * 1024;

/// Taille d'une pièce une fois encodée en Base64 (hors préfixe `data:…`).
int tailleBase64(int octets) => ((octets + 2) ~/ 3) * 4;

/// Le repli en image encodée est-il permis pour cette pièce ? Photos seulement
/// (jamais un PDF), et assez petites pour que les règles Firestore puissent
/// encore évaluer le profil.
bool repliBase64Possible(TypePiece type, int octets) => type.estImage && octets <= limiteOctetsRepliBase64;

/// Code d'un échec d'écriture Firestore. Après un repli, il garde la cause de
/// l'échec de Storage : c'est elle qu'il faut corriger, pas l'écriture de secours.
String codeEchecFirestore(String codeFirestore, {String? codeStockage}) =>
    codeStockage == null ? 'firestore/$codeFirestore' : 'firestore/$codeFirestore, repli après $codeStockage';

/// Le fichier choisi n'est pas une photo JPEG/PNG/WebP ni un PDF.
class FormatPieceNonSupporteException implements Exception {
  const FormatPieceNonSupporteException({this.heic = false});

  final bool heic;
}

/// Photo ou fichier trop lourd (10 Mo au plus, comme les règles Storage).
class DocumentTropVolumineuxException implements Exception {
  const DocumentTropVolumineuxException();
}

/// L'envoi a échoué pour une raison précise, que [code] reprend
/// (`storage/unauthorized`, `firestore/permission-denied`, `reseau/delai`…).
/// L'écran l'affiche pour que l'équipe puisse savoir exactement ce qui s'est passé.
class EchecEnvoiPieceException implements Exception {
  const EchecEnvoiPieceException(this.code, {this.cause});

  final String code;
  final Object? cause;

  @override
  String toString() => 'EchecEnvoiPieceException($code, $cause)';
}

/// Code court d'une erreur Firebase, ex. `storage/unauthorized`.
String codeFirebase(String service, FirebaseException e) => '$service/${e.code}';

/// Message affiché au chauffeur quand l'envoi d'une pièce échoue. Il ne cache
/// jamais la cause : un code précis est indiqué pour les échecs techniques.
String messageErreurEnvoi(Object erreur) {
  if (erreur is DocumentTropVolumineuxException) {
    return 'Ce fichier est trop volumineux (10 Mo au plus). Choisissez-en un plus léger.';
  }
  if (erreur is FormatPieceNonSupporteException) {
    if (erreur.heic) {
      return 'Cette photo est au format HEIC, que Sprint ne peut pas lire. Reprenez-la en JPEG '
          '(iPhone : Réglages > Appareil photo > Formats > Le plus compatible) ou envoyez un PDF.';
    }
    return 'Format non pris en charge. Envoyez une photo (JPEG, PNG ou WebP) ou un PDF.';
  }
  if (erreur is EchecEnvoiPieceException) {
    return "Échec de l'envoi (code : ${erreur.code}). Réessayez ; si cela continue, indiquez ce code au support.";
  }
  return "Échec de l'envoi (code : ${erreur.runtimeType}). Réessayez ; si cela continue, indiquez ce code au support.";
}
