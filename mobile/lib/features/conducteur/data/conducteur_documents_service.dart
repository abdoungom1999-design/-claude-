import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Photo trop lourde pour être acceptée (voir les plafonds de
/// [ConducteurDocumentsService]).
class DocumentTropVolumineuxException implements Exception {
  const DocumentTropVolumineuxException();
}

/// Envoi des documents chauffeur (KYC + photo de profil).
///
/// Chemin principal : le fichier est téléversé dans Firebase Storage
/// (`kyc_documents/{uid}/{cle}.jpg`), et seule son URL de
/// téléchargement est enregistrée dans Firestore
/// (`users/{uid}.documents.{cle}`) — plus d'image encodée qui alourdit
/// chaque lecture du profil, ni de plafond de 1 Mo par document
/// Firestore.
///
/// Repli : si Storage refuse l'envoi (service pas encore activé sur le
/// projet, règles non déployées…), on retombe sur l'ancien stockage
/// Base64 dans Firestore, pour ne jamais bloquer l'inscription d'un
/// chauffeur. Les lecteurs ([ImageDocument]) acceptent les deux
/// formats, ce qui couvre aussi les documents envoyés avant cette
/// migration.
class ConducteurDocumentsService {
  /// Plafond côté Storage : large, mais évite qu'une photo brute non
  /// compressée (le Web ignore parfois la compression d'`image_picker`)
  /// ne consomme inutilement stockage et bande passante.
  static const int limiteOctetsStorage = 5 * 1024 * 1024;

  /// Plafond du repli Base64 : plusieurs documents doivent tenir dans le
  /// même document `users/{uid}`, bien en dessous du 1 Mo de Firestore.
  static const int limiteOctetsBase64 = 700 * 1024;

  /// Mémorise, pour la session, qu'une tentative Storage a échoué :
  /// évite de refaire à chaque document un aller-retour voué à l'échec.
  static bool _storageIndisponible = false;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Enregistre [octets] sous la clé [cle] ('permis', 'carteGrise',
  /// 'attestationVtc' ou 'photoProfil') sans toucher aux autres
  /// documents, et remet le dossier en file d'attente de vérification
  /// Admin (`statutValidation: 'en_attente'`).
  Future<void> televerserDocument({
    required String uid,
    required String cle,
    required Uint8List octets,
  }) async {
    if (octets.lengthInBytes > limiteOctetsStorage) {
      throw const DocumentTropVolumineuxException();
    }

    final valeur = await _televerserVersStorage(uid: uid, cle: cle, octets: octets) ??
        _encoderEnBase64(octets);

    await _firestore.collection('users').doc(uid).update({
      'documents.$cle': valeur,
      'statutValidation': 'en_attente',
    });
  }

  /// Renvoie l'URL de téléchargement, ou `null` si Storage est
  /// indisponible (l'appelant bascule alors sur le Base64).
  Future<String?> _televerserVersStorage({
    required String uid,
    required String cle,
    required Uint8List octets,
  }) async {
    if (_storageIndisponible) return null;
    try {
      final storage = FirebaseStorage.instance
        ..setMaxUploadRetryTime(const Duration(seconds: 20));
      final reference = storage.ref('kyc_documents/$uid/$cle.jpg');
      await reference.putData(octets, SettableMetadata(contentType: 'image/jpeg'));
      return await reference.getDownloadURL();
    } on FirebaseException catch (e) {
      debugPrint('Firebase Storage indisponible (${e.code}) : repli Base64.');
      _storageIndisponible = true;
      return null;
    }
  }

  String _encoderEnBase64(Uint8List octets) {
    if (octets.lengthInBytes > limiteOctetsBase64) {
      throw const DocumentTropVolumineuxException();
    }
    return 'data:image/jpeg;base64,${base64Encode(octets)}';
  }
}
