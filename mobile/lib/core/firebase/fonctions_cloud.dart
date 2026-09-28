import 'package:cloud_functions/cloud_functions.dart';
import '../network/api_exception.dart';

/// Accès aux Cloud Functions de Sprint (dossier `functions/`), déployées
/// dans la même région que celle déclarée dans `functions/src/index.ts`.
abstract final class FonctionsCloud {
  static const region = 'europe-west1';

  static FirebaseFunctions get instance => FirebaseFunctions.instanceFor(region: region);

  /// Appelle la fonction [nom] et renvoie sa réponse (un objet JSON).
  static Future<Map<String, dynamic>> appeler(String nom, Map<String, dynamic> donnees) async {
    final resultat = await instance.httpsCallable(nom).call<Object?>(donnees);
    return Map<String, dynamic>.from(resultat.data as Map);
  }

  /// Message affichable pour une erreur d'appel : les messages de
  /// validation du serveur sont déjà rédigés pour le client.
  static ApiException versApiException(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'invalid-argument':
      case 'permission-denied':
      case 'failed-precondition':
        return ApiException(e.message ?? 'Demande refusée.');
      case 'unauthenticated':
        return ApiException('Votre session a expiré. Reconnectez-vous.');
      default:
        return ApiException('Impossible de contacter le serveur. Vérifiez votre connexion.');
    }
  }
}
