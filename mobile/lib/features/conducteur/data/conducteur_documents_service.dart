import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Dépassement possible si l'image n'est pas compressée par
/// `image_picker` sur certaines plateformes (voir [televerserDocument]).
class DocumentTropVolumineuxException implements Exception {
  const DocumentTropVolumineuxException();
}

/// Solution TEMPORAIRE de stockage des documents chauffeur (KYC) :
/// encode chaque photo en Base64 directement dans le document
/// Firestore `users/{uid}.documents.{cle}`, en l'absence pour l'instant
/// d'un vrai bucket Firebase Storage. À remplacer dès que Storage est
/// activé côté Groupe Santine : Storage n'a pas la limite de 1 Mo par
/// document de Firestore, et évite d'alourdir chaque lecture du profil
/// avec des images encodées.
///
/// Sécurité de taille : Firestore refuse tout document dépassant 1 Mo
/// au total (tous champs confondus). `image_picker` compresse déjà
/// l'image (voir les paramètres passés à `pickImage` côté UI), mais
/// cette compression n'est pas garantie sur toutes les plateformes
/// (le Web, en particulier, l'ignore parfois). [televerserDocument]
/// vérifie donc la taille avant d'écrire, et lève
/// [DocumentTropVolumineuxException] plutôt que de risquer un document
/// corrompu ou un échec d'écriture Firestore peu clair.
class ConducteurDocumentsService {
  /// Limite volontairement prudente : plusieurs documents doivent
  /// pouvoir cohabiter dans le même document `users/{uid}` (bien en
  /// dessous du 1 Mo total de Firestore).
  static const int limiteOctetsParDocument = 700 * 1024;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Encode [octets] en Base64 (data URI) et l'enregistre sous
  /// `users/{uid}.documents.{cle}`, en ne touchant à aucun autre champ
  /// (dont les autres documents déjà téléversés). Marque aussi
  /// `statutValidation: 'en_attente'` : tout nouveau document remet le
  /// dossier en file d'attente de vérification côté Admin.
  Future<void> televerserDocument({
    required String uid,
    required String cle,
    required Uint8List octets,
  }) async {
    if (octets.lengthInBytes > limiteOctetsParDocument) {
      throw const DocumentTropVolumineuxException();
    }
    final donneesBase64 = 'data:image/jpeg;base64,${base64Encode(octets)}';
    await _firestore.collection('users').doc(uid).update({
      'documents.$cle': donneesBase64,
      'statutValidation': 'en_attente',
    });
  }
}
