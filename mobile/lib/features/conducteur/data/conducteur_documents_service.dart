import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../../core/suivi/suivi_plantages.dart';
import 'piece_kyc.dart';

export 'piece_kyc.dart'
    show
        DocumentTropVolumineuxException,
        EchecEnvoiPieceException,
        FormatPieceNonSupporteException,
        TypePiece,
        messageErreurEnvoi;

/// Envoi des documents chauffeur (KYC + photo de profil).
///
/// Chemin principal : le fichier est téléversé dans Firebase Storage
/// (`kyc_documents/{uid}/{cle}.jpg` pour une photo, `{cle}.pdf` pour un PDF),
/// avec son type RÉEL (reconnu d'après son contenu, voir [detecterTypePiece]),
/// et seule son URL de téléchargement est enregistrée dans Firestore
/// (`users/{uid}.documents.{cle}`).
///
/// Repli (photos seulement) : si Storage refuse l'envoi, on retombe sur
/// l'ancien stockage Base64 dans Firestore (700 Ko au plus), pour ne pas
/// bloquer un chauffeur. Les lecteurs ([ImageDocument]) acceptent les deux
/// formats.
///
/// Plus d'échec silencieux : la cause exacte de chaque échec est consignée
/// (console du navigateur, Crashlytics sur Android) et remontée à l'écran sous
/// forme de code ([EchecEnvoiPieceException]).
class ConducteurDocumentsService {
  /// Plafond d'une pièce (photo ou PDF), identique à celui des règles Storage.
  static const int limiteOctetsStorage = 10 * 1024 * 1024;

  /// Plafond du repli Base64 : plusieurs documents doivent tenir dans le
  /// même document `users/{uid}`, bien en dessous du 1 Mo de Firestore.
  static const int limiteOctetsBase64 = 700 * 1024;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Enregistre [octets] sous la clé [cle] ('carteIdentite', 'carteGrise',
  /// 'photoProfil' ; 'permis' et 'attestationVtc' pour les anciens dossiers)
  /// sans toucher aux autres documents, et remet le dossier en file
  /// d'attente de vérification Admin (`statutValidation: 'en_attente'`).
  ///
  /// Lève [FormatPieceNonSupporteException], [DocumentTropVolumineuxException]
  /// ou [EchecEnvoiPieceException] (avec le code précis de la cause).
  Future<void> televerserDocument({
    required String uid,
    required String cle,
    required Uint8List octets,
  }) async {
    final type = detecterTypePiece(octets);
    if (type == null) throw FormatPieceNonSupporteException(heic: estPieceHeic(octets));
    if (octets.lengthInBytes > limiteOctetsStorage) throw const DocumentTropVolumineuxException();

    String? valeur;
    String? codeStorage;
    try {
      valeur = await _televerserVersStorage(uid: uid, cle: cle, octets: octets, type: type);
    } on FirebaseException catch (e, pile) {
      codeStorage = codeFirebase('storage', e);
      _consigner('Storage', e, pile);
    } on Object catch (e, pile) {
      // Délai dépassé, réseau coupé, navigateur : pas une erreur Firebase.
      codeStorage = 'storage/${e.runtimeType}';
      _consigner('Storage', e, pile);
    }

    // Repli Base64 : photos seulement, et seulement si elles tiennent.
    if (valeur == null && type.estImage && octets.lengthInBytes <= limiteOctetsBase64) {
      valeur = 'data:${type.contentType};base64,${base64Encode(octets)}';
    }
    if (valeur == null) {
      throw EchecEnvoiPieceException(codeStorage ?? 'storage/inconnu');
    }

    try {
      await _firestore.collection('users').doc(uid).update({
        'documents.$cle': valeur,
        'statutValidation': 'en_attente',
      });
    } on FirebaseException catch (e, pile) {
      _consigner('Firestore', e, pile);
      throw EchecEnvoiPieceException(codeFirebase('firestore', e), cause: e);
    }
  }

  /// Renvoie l'URL de téléchargement. Toute erreur est remontée à l'appelant.
  Future<String> _televerserVersStorage({
    required String uid,
    required String cle,
    required Uint8List octets,
    required TypePiece type,
  }) async {
    final storage = FirebaseStorage.instance..setMaxUploadRetryTime(const Duration(seconds: 60));
    final reference = storage.ref('kyc_documents/$uid/$cle.${type.estImage ? 'jpg' : 'pdf'}');
    await reference.putData(octets, SettableMetadata(contentType: type.contentType));
    final url = await reference.getDownloadURL();
    // Une pièce remplacée par un fichier d'un autre genre (photo -> PDF ou
    // l'inverse) ne laisse pas l'ancienne copie dans Storage. Sans importance
    // si elle n'existe pas.
    try {
      await storage.ref('kyc_documents/$uid/$cle.${type.estImage ? 'pdf' : 'jpg'}').delete();
    } on Object {
      // Rien à supprimer, ou suppression refusée : l'envoi lui-même a réussi.
    }
    return url;
  }

  /// Consigne la cause exacte d'un échec : console (visible dans le navigateur)
  /// et, sur Android en version finale, Crashlytics (sans nom ni identifiant).
  void _consigner(String etape, Object erreur, StackTrace pile) {
    debugPrint('Envoi document KYC, $etape : $erreur');
    if (SuiviDesPlantages.instance.actif) {
      try {
        FirebaseCrashlytics.instance.recordError(erreur, pile, reason: 'envoi_document_kyc_$etape', fatal: false);
      } on Object {
        // Le suivi ne doit jamais gêner l'envoi.
      }
    }
  }
}
