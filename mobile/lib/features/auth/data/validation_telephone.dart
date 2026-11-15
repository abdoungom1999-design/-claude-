import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../../core/firebase/fonctions_cloud.dart';
import '../../../core/network/api_exception.dart';
import '../../../firebase_options.dart';
import '../../portefeuille/data/retraits.dart' show numeroSenegal;

/// Validation du numéro de téléphone par SMS (code à 6 chiffres).
///
/// Firebase Phone Auth envoie le SMS et contrôle le code ; mais un numéro
/// Firebase ne peut appartenir qu'à UN compte, alors que Sprint permet le même
/// numéro à un compte Client et à un compte Chauffeur. Le contrôle se fait donc
/// sur une SESSION SECONDAIRE (une seconde application Firebase du même
/// projet) : la session de la personne, connectée par e-mail, n'est jamais
/// touchée. Le jeton d'identité de la session « téléphone » est ensuite remis
/// au serveur (`validerTelephone`), qui le vérifie auprès de Google et pose la
/// marque « numéro validé » sur le compte (voir `functions/src/inscription.ts`).
/// L'app ne peut pas poser cette marque elle-même (règles Firestore).

/// Un SMS envoyé : de quoi contrôler le code qui sera saisi.
class EnvoiSms {
  const EnvoiSms({this.identifiant, this.jetonRenvoi, this.confirmationWeb});

  /// Téléphone (Android) : identifiant de la vérification en cours.
  final String? identifiant;

  /// Téléphone (Android) : permet de redemander un code sans nouvelle vérification anti-abus.
  final int? jetonRenvoi;

  /// Site : confirmation en attente du code (`ConfirmationResult` de Firebase).
  final Object? confirmationWeb;
}

/// L'accès à Firebase Phone Auth, remplaçable par un faux dans les tests.
abstract class PasserelleSms {
  /// Envoie le code au [numero] (format international). [precedent] : envoi
  /// précédent, pour un renvoi. [surVerificationAutomatique] : Android a lu le
  /// SMS (ou reconnu le numéro) sans saisie ; le jeton est déjà prêt.
  Future<EnvoiSms> envoyer(
    String numero, {
    EnvoiSms? precedent,
    required void Function(String jeton) surVerificationAutomatique,
  });

  /// Contrôle le [code] saisi ; rend le jeton d'identité de la session « téléphone ».
  Future<String> confirmer(EnvoiSms envoi, String code);

  /// Ferme la session « téléphone » (jamais celle de la personne).
  Future<void> terminer();
}

/// Message affichable pour une erreur de Firebase Phone Auth.
ApiException erreurTelephone(FirebaseAuthException e) {
  // Code technique visible dans la console (diagnostic des réglages de la console Firebase).
  debugPrint('Phone Auth : ${e.code} ${e.message ?? ''}');
  switch (e.code) {
    case 'invalid-phone-number':
      return ApiException("Ce numéro n'est pas valide. Vérifiez-le (exemple : 77 123 45 67).");
    case 'invalid-verification-code':
      return ApiException('Code incorrect. Vérifiez-le et réessayez.');
    case 'session-expired':
    case 'code-expired':
    case 'invalid-verification-id':
      return ApiException('Ce code a expiré. Demandez-en un nouveau.');
    case 'too-many-requests':
      return ApiException('Trop de demandes. Réessayez dans quelques minutes.');
    case 'quota-exceeded':
      return ApiException("L'envoi de SMS est momentanément saturé. Réessayez plus tard.");
    case 'network-request-failed':
      return ApiException('Impossible de contacter le serveur. Vérifiez votre connexion.');
    case 'user-disabled':
      return ApiException('Ce numéro ne peut pas être utilisé.');
    case 'web-context-cancelled':
    case 'captcha-check-failed':
      return ApiException("La vérification de sécurité n'a pas abouti. Réessayez.");
    default:
      // operation-not-allowed, app-not-authorized, missing-client-identifier…
      // (réglages de la console Firebase non faits) : rien d'utile à dire à la personne.
      return ApiException("L'envoi du code est momentanément indisponible. Réessayez plus tard.");
  }
}

/// Vrai Firebase Phone Auth, sur une application Firebase secondaire.
class PasserelleSmsFirebase implements PasserelleSms {
  static const _nomApplication = 'verification-telephone';

  FirebaseAuth? _auth;

  Future<FirebaseAuth> _instance() async {
    final existante = _auth;
    if (existante != null) return existante;
    final app = Firebase.apps.where((a) => a.name == _nomApplication).firstOrNull ??
        await Firebase.initializeApp(name: _nomApplication, options: DefaultFirebaseOptions.currentPlatform);
    final auth = FirebaseAuth.instanceFor(app: app);
    // SMS rédigé en français.
    await auth.setLanguageCode('fr');
    return _auth = auth;
  }

  @override
  Future<EnvoiSms> envoyer(
    String numero, {
    EnvoiSms? precedent,
    required void Function(String jeton) surVerificationAutomatique,
  }) async {
    final auth = await _instance();
    try {
      if (kIsWeb) {
        // Site (navigateur, iPhone) : reCAPTCHA invisible géré par Firebase.
        return EnvoiSms(confirmationWeb: await auth.signInWithPhoneNumber(numero));
      }
      final envoi = Completer<EnvoiSms>();
      await auth.verifyPhoneNumber(
        phoneNumber: numero,
        timeout: const Duration(seconds: 60),
        forceResendingToken: precedent?.jetonRenvoi,
        verificationCompleted: (identifiants) async {
          // Vérification instantanée, ou SMS lu automatiquement : pas de saisie.
          try {
            final connexion = await auth.signInWithCredential(identifiants);
            final jeton = await connexion.user?.getIdToken();
            if (jeton != null) surVerificationAutomatique(jeton);
          } on Object catch (e) {
            debugPrint('Phone Auth : vérification automatique impossible ($e)');
          }
        },
        verificationFailed: (e) {
          if (!envoi.isCompleted) envoi.completeError(erreurTelephone(e));
        },
        codeSent: (identifiant, jetonRenvoi) {
          if (!envoi.isCompleted) envoi.complete(EnvoiSms(identifiant: identifiant, jetonRenvoi: jetonRenvoi));
        },
        codeAutoRetrievalTimeout: (_) {},
      );
      return await envoi.future;
    } on FirebaseAuthException catch (e) {
      throw erreurTelephone(e);
    }
  }

  @override
  Future<String> confirmer(EnvoiSms envoi, String code) async {
    final auth = await _instance();
    try {
      final UserCredential identifiants;
      final confirmation = envoi.confirmationWeb;
      if (confirmation is ConfirmationResult) {
        identifiants = await confirmation.confirm(code);
      } else {
        final identifiant = envoi.identifiant;
        if (identifiant == null) throw ApiException('Ce code a expiré. Demandez-en un nouveau.');
        identifiants = await auth.signInWithCredential(
          PhoneAuthProvider.credential(verificationId: identifiant, smsCode: code),
        );
      }
      final jeton = await identifiants.user?.getIdToken();
      if (jeton == null) throw ApiException("Le code n'a pas pu être contrôlé. Réessayez.");
      return jeton;
    } on FirebaseAuthException catch (e) {
      throw erreurTelephone(e);
    }
  }

  @override
  Future<void> terminer() async {
    try {
      await _auth?.signOut();
    } on Object catch (e) {
      debugPrint('Phone Auth : session « téléphone » non fermée ($e)');
    }
  }
}

/// Appel d'une fonction du serveur (réponse = objet JSON), remplaçable dans les tests.
typedef AppelServeur = Future<Map<String, dynamic>> Function(String nom, Map<String, dynamic> donnees);

/// Numéro mobile sénégalais au format international (« +221771234567 »), `null` sinon.
String? telephoneInternational(String saisie) {
  final numero = numeroSenegal(saisie);
  return numero == null ? null : '+221$numero';
}

/// Le numéro du profil est-il validé ? La marque du serveur ne vaut que pour le
/// numéro qu'elle a contrôlé : un numéro modifié depuis n'est plus validé.
bool numeroValide(Map<String, dynamic>? profil) {
  if (profil == null || profil['telephoneVerifie'] != true) return false;
  final actuel = telephoneInternational(profil['telephone'] as String? ?? '');
  return actuel != null && actuel == profil['telephoneValide'];
}

/// Parcours de validation : envoi du code, contrôle, preuve remise au serveur.
class ValidationTelephone {
  ValidationTelephone({PasserelleSms? passerelle, AppelServeur? appel})
      : _passerelle = passerelle ?? PasserelleSmsFirebase(),
        _appel = appel ?? FonctionsCloud.appeler;

  final PasserelleSms _passerelle;
  final AppelServeur _appel;

  /// Envoie le code par SMS au numéro saisi. Erreurs : [ApiException] (messages en français).
  Future<EnvoiSms> envoyerCode(
    String saisie, {
    EnvoiSms? precedent,
    required void Function(String jeton) surVerificationAutomatique,
  }) {
    final numero = telephoneInternational(saisie);
    if (numero == null) {
      throw ApiException('Entrez un numéro mobile du Sénégal (exemple : 77 123 45 67).');
    }
    return _passerelle.envoyer(numero, precedent: precedent, surVerificationAutomatique: surVerificationAutomatique);
  }

  /// Contrôle le code saisi puis demande au serveur de marquer le numéro validé.
  Future<void> confirmerCode(EnvoiSms envoi, String code) async {
    final propre = code.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(propre)) throw ApiException('Entrez les 6 chiffres du code.');
    await validerAupresDuServeur(await _passerelle.confirmer(envoi, propre));
  }

  /// Remet au serveur la preuve (jeton de la session « téléphone »), puis ferme cette session.
  Future<void> validerAupresDuServeur(String jeton) async {
    try {
      await _appel('validerTelephone', {'jeton': jeton});
    } on FirebaseFunctionsException catch (e) {
      throw FonctionsCloud.versApiException(e);
    } finally {
      unawaited(_passerelle.terminer());
    }
  }

  /// Ferme la session « téléphone » (page quittée avant la fin).
  Future<void> abandonner() => _passerelle.terminer();
}
