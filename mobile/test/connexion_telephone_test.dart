import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/network/api_exception.dart';
import 'package:sprint/features/auth/data/auth_repository.dart';
import 'package:sprint/features/auth/data/connexion_telephone.dart';

/// Faux serveur : enregistre les appels et répond comme on le lui demande.
class _Serveur {
  final appels = <({String nom, Map<String, dynamic> donnees})>[];
  Object? erreur;
  Map<String, dynamic> reponse = {'email': 'awa@test.sn'};

  Future<Map<String, dynamic>> appeler(String nom, Map<String, dynamic> donnees) async {
    appels.add((nom: nom, donnees: donnees));
    final e = erreur;
    if (e != null) throw e;
    return reponse;
  }
}

FirebaseFunctionsException _erreur(String code, [String message = 'message du serveur']) =>
    FirebaseFunctionsException(code: code, message: message);

Future<ApiException> _refus(Future<Object?> appel) async {
  try {
    await appel;
  } on ApiException catch (e) {
    return e;
  }
  fail("l'appel aurait dû être refusé");
}

void main() {
  group('Connexion par téléphone : résolution côté serveur', () {
    test('le serveur reçoit rôle, numéro (espaces retirés) et mot de passe, et rend l\'e-mail', () async {
      final serveur = _Serveur();
      final email = await ConnexionTelephone(appeler: serveur.appeler)
          .emailPour(role: 'client', telephone: '  +221771111111 ', motDePasse: 'secret');

      expect(email, 'awa@test.sn');
      expect(serveur.appels, hasLength(1));
      expect(serveur.appels.single.nom, 'connexionTelephone');
      expect(serveur.appels.single.donnees, {'role': 'client', 'telephone': '+221771111111', 'motDePasse': 'secret'});
    });

    test('numéro ou mot de passe refusé : un seul message, sans rien dire du compte', () async {
      for (final code in ['permission-denied', 'invalid-argument']) {
        final serveur = _Serveur()..erreur = _erreur(code, 'détail interne du serveur');
        final e = await _refus(
          ConnexionTelephone(appeler: serveur.appeler).emailPour(role: 'client', telephone: '77', motDePasse: 'x'),
        );
        expect(e.message, ConnexionTelephone.messageIdentifiants, reason: code);
      }
    });

    test('trop d\'essais, service en panne, fonction absente : des messages distincts et utiles', () async {
      final attendus = {
        'resource-exhausted': ConnexionTelephone.messageTropDEssais,
        'unavailable': ConnexionTelephone.messageIndisponible,
        'internal': ConnexionTelephone.messageIndisponible,
        'not-found': ConnexionTelephone.messageIndisponible,
        'deadline-exceeded': ConnexionTelephone.messageIndisponible,
        'unauthenticated': 'Impossible de contacter le serveur. Vérifiez votre connexion.',
      };
      for (final entree in attendus.entries) {
        final serveur = _Serveur()..erreur = _erreur(entree.key);
        final e = await _refus(
          ConnexionTelephone(appeler: serveur.appeler).emailPour(role: 'conducteur', telephone: '77', motDePasse: 'x'),
        );
        expect(e.message, entree.value, reason: entree.key);
      }
    });

    test('réponse sans e-mail exploitable : indisponible, jamais un e-mail inventé', () async {
      for (final reponse in <Map<String, dynamic>>[{}, {'email': ''}, {'email': 12}, {'autre': 'x'}]) {
        final serveur = _Serveur()..reponse = reponse;
        final e = await _refus(
          ConnexionTelephone(appeler: serveur.appeler).emailPour(role: 'client', telephone: '77', motDePasse: 'x'),
        );
        expect(e.message, ConnexionTelephone.messageIndisponible);
      }
    });

    test('annuaire : l\'app demande au serveur de publier l\'entrée du compte, et ne bloque jamais', () async {
      final serveur = _Serveur();
      await ConnexionTelephone(appeler: serveur.appeler).synchroniserAnnuaire();
      expect(serveur.appels.single.nom, 'synchroniserAnnuaire');

      final enPanne = _Serveur()..erreur = _erreur('unavailable');
      await ConnexionTelephone(appeler: enPanne.appeler).synchroniserAnnuaire(); // aucune exception
      final inattendu = _Serveur()..erreur = StateError('plantage');
      await ConnexionTelephone(appeler: inattendu.appeler).synchroniserAnnuaire();
    });

    test('la clé d\'annuaire de l\'app reste alignée sur celle du serveur (rôle_numéro, sans barre oblique)', () {
      expect(AuthRepository.cleAnnuaire('client', ' +221771111111 '), 'client_+221771111111');
      expect(AuthRepository.cleAnnuaire('conducteur', '77/12'), isNull);
      expect(AuthRepository.cleAnnuaire('client', '  '), isNull);
    });
  });
}
