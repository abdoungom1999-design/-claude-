import 'package:cloud_functions/cloud_functions.dart';
import '../../../core/firebase/fonctions_cloud.dart';
import '../../../core/network/api_exception.dart';

/// Appel d'une Cloud Function (injectable pour les tests).
typedef AppelFonction = Future<Map<String, dynamic>> Function(String nom, Map<String, dynamic> donnees);

/// Connexion par numéro de téléphone, côté serveur.
///
/// L'annuaire `annuaire_telephones` (téléphone -> e-mail) n'est plus lisible
/// par l'app : n'importe qui pouvait y tester des numéros pour savoir qui a
/// un compte Sprint et récupérer son e-mail. Le serveur ([connexionTelephone],
/// `functions/src/connexion_telephone.ts`) vérifie le mot de passe et ne rend
/// l'e-mail qu'à celui qui le connaît ; l'app termine ensuite la connexion
/// avec Firebase Auth, comme avec un e-mail. Numéro inconnu et mot de passe
/// faux donnent le même message.
class ConnexionTelephone {
  ConnexionTelephone({AppelFonction? appeler}) : _appeler = appeler ?? FonctionsCloud.appeler;

  final AppelFonction _appeler;

  static const messageIdentifiants = 'Numéro ou mot de passe incorrect.';
  static const messageTropDEssais = 'Trop de tentatives. Réessayez dans quelques minutes.';
  static const messageIndisponible =
      'La connexion par téléphone est momentanément indisponible. Utilisez votre e-mail.';

  /// E-mail du compte de ce numéro, si [motDePasse] est le bon. Lève une
  /// [ApiException] affichable sinon.
  Future<String> emailPour({
    required String role,
    required String telephone,
    required String motDePasse,
  }) async {
    final Map<String, dynamic> reponse;
    try {
      reponse = await _appeler('connexionTelephone', {
        'role': role,
        'telephone': telephone.trim(),
        'motDePasse': motDePasse,
      });
    } on FirebaseFunctionsException catch (e) {
      throw traduire(e);
    }
    final email = reponse['email'];
    if (email is! String || email.isEmpty) throw ApiException(messageIndisponible);
    return email;
  }

  /// Publie l'entrée d'annuaire du compte connecté (numéro de son profil) :
  /// l'app n'a plus le droit d'écrire dans l'annuaire. Jamais bloquant : un
  /// échec désactive seulement la connexion par téléphone pour ce compte.
  Future<void> synchroniserAnnuaire() async {
    try {
      await _appeler('synchroniserAnnuaire', const {});
    } catch (_) {
      // Voir ci-dessus : volontairement silencieux.
    }
  }

  /// Message affichable pour une réponse d'erreur du serveur.
  static ApiException traduire(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'permission-denied':
      case 'invalid-argument':
        return ApiException(messageIdentifiants);
      case 'resource-exhausted':
        return ApiException(messageTropDEssais);
      case 'unavailable':
      case 'internal':
      case 'not-found':
      case 'unimplemented':
      case 'deadline-exceeded':
        return ApiException(messageIndisponible);
      default:
        return ApiException('Impossible de contacter le serveur. Vérifiez votre connexion.');
    }
  }
}
