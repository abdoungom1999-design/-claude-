// Validation du numéro par SMS : service (preuve remise au serveur) et écran du code à 6 chiffres.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/network/api_exception.dart';
import 'package:sprint/features/auth/data/validation_telephone.dart';
import 'package:sprint/features/auth/presentation/validation_telephone_page.dart';

/// Faux Firebase Phone Auth : enregistre ce qu'on lui demande, répond comme on le lui dit.
class _Passerelle implements PasserelleSms {
  final envois = <({String numero, EnvoiSms? precedent})>[];
  final confirmations = <String>[];
  int terminees = 0;
  Object? erreurEnvoi;
  Object? erreurConfirmation;
  void Function(String jeton)? verificationAutomatique;

  @override
  Future<EnvoiSms> envoyer(
    String numero, {
    EnvoiSms? precedent,
    required void Function(String jeton) surVerificationAutomatique,
  }) async {
    envois.add((numero: numero, precedent: precedent));
    verificationAutomatique = surVerificationAutomatique;
    final e = erreurEnvoi;
    if (e != null) throw e;
    return EnvoiSms(identifiant: 'verif-${envois.length}', jetonRenvoi: envois.length);
  }

  @override
  Future<String> confirmer(EnvoiSms envoi, String code) async {
    confirmations.add('${envoi.identifiant}:$code');
    final e = erreurConfirmation;
    if (e != null) throw e;
    return 'jeton-telephone-$code';
  }

  @override
  Future<void> terminer() async => terminees++;
}

class _Serveur {
  final appels = <({String nom, Map<String, dynamic> donnees})>[];
  Object? erreur;

  Future<Map<String, dynamic>> appeler(String nom, Map<String, dynamic> donnees) async {
    appels.add((nom: nom, donnees: donnees));
    final e = erreur;
    if (e != null) throw e;
    return {'valide': true, 'telephone': '+221771234567'};
  }
}

Future<ApiException> _refus(Future<Object?> appel) async {
  try {
    await appel;
  } on ApiException catch (e) {
    return e;
  }
  fail("l'appel aurait dû être refusé");
}

void main() {
  group('Numéro et marque du serveur', () {
    test('format international : seulement les mobiles du Sénégal, quelle que soit la saisie', () {
      for (final saisie in ['77 123 45 67', '771234567', '+221 77 123 45 67', '00221771234567', '221771234567', '77-123-45-67']) {
        expect(telephoneInternational(saisie), '+221771234567', reason: saisie);
      }
      for (final refus in ['', '12345', '+33612345678', '+221331234567', '7712345', 'abc']) {
        expect(telephoneInternational(refus), isNull, reason: refus);
      }
    });

    test('le numéro est validé tant qu\'il est celui que le serveur a contrôlé, plus après une modification', () {
      final valide = {'telephone': '77 123 45 67', 'telephoneVerifie': true, 'telephoneValide': '+221771234567'};
      expect(numeroValide(valide), isTrue);
      expect(numeroValide({...valide, 'telephone': '+221 77 123 45 67'}), isTrue, reason: 'autre écriture du même numéro');
      expect(numeroValide({...valide, 'telephone': '76 234 56 78'}), isFalse, reason: 'numéro modifié depuis');
      expect(numeroValide({...valide, 'telephoneVerifie': false}), isFalse);
      expect(numeroValide({'telephone': '77 123 45 67'}), isFalse, reason: 'jamais validé');
      expect(numeroValide({...valide, 'telephone': 'pas un numéro'}), isFalse);
      expect(numeroValide(null), isFalse);
    });
  });

  group('Service : envoi du code, contrôle, preuve remise au serveur', () {
    test('le code est demandé au numéro en format international, en passant le renvoi', () async {
      final passerelle = _Passerelle();
      final service = ValidationTelephone(passerelle: passerelle, appel: _Serveur().appeler);

      final premier = await service.envoyerCode('77 123 45 67', surVerificationAutomatique: (_) {});
      final second = await service.envoyerCode('77 123 45 67', precedent: premier, surVerificationAutomatique: (_) {});

      expect(passerelle.envois.map((e) => e.numero), ['+221771234567', '+221771234567']);
      expect(passerelle.envois[1].precedent, same(premier));
      expect(second.jetonRenvoi, 2);
    });

    test('un numéro qui n\'est pas un mobile du Sénégal est refusé sans rien envoyer', () async {
      final passerelle = _Passerelle();
      final service = ValidationTelephone(passerelle: passerelle, appel: _Serveur().appeler);
      final e = await _refus(Future.sync(() => service.envoyerCode('+33 6 12 34 56 78', surVerificationAutomatique: (_) {})));
      expect(e.message, contains('Sénégal'));
      expect(passerelle.envois, isEmpty);
    });

    test('code juste : le serveur reçoit le jeton de la session « téléphone » (et lui seul), puis elle est fermée', () async {
      final passerelle = _Passerelle();
      final serveur = _Serveur();
      final service = ValidationTelephone(passerelle: passerelle, appel: serveur.appeler);
      final envoi = await service.envoyerCode('77 123 45 67', surVerificationAutomatique: (_) {});

      await service.confirmerCode(envoi, '123 456');

      expect(passerelle.confirmations, ['verif-1:123456']);
      expect(serveur.appels, hasLength(1));
      expect(serveur.appels.single.nom, 'validerTelephone');
      expect(serveur.appels.single.donnees, {'jeton': 'jeton-telephone-123456'}, reason: 'ni numéro ni rôle envoyés : le serveur lit le jeton');
      await Future<void>.delayed(Duration.zero);
      expect(passerelle.terminees, 1);
    });

    test('un code qui n\'a pas 6 chiffres n\'est même pas envoyé à Firebase', () async {
      final passerelle = _Passerelle();
      final service = ValidationTelephone(passerelle: passerelle, appel: _Serveur().appeler);
      const envoi = EnvoiSms(identifiant: 'v');
      for (final code in ['', '12345', '1234567', 'abcdef', '12 34']) {
        final e = await _refus(service.confirmerCode(envoi, code));
        expect(e.message, 'Entrez les 6 chiffres du code.', reason: code);
      }
      expect(passerelle.confirmations, isEmpty);
    });

    test('code refusé par Firebase : message clair, rien n\'est demandé au serveur', () async {
      final passerelle = _Passerelle()..erreurConfirmation = erreurTelephone(FirebaseAuthException(code: 'invalid-verification-code'));
      final serveur = _Serveur();
      final service = ValidationTelephone(passerelle: passerelle, appel: serveur.appeler);
      final e = await _refus(service.confirmerCode(const EnvoiSms(identifiant: 'v'), '000000'));
      expect(e.message, 'Code incorrect. Vérifiez-le et réessayez.');
      expect(serveur.appels, isEmpty);
    });

    test('numéro déjà validé ailleurs, code expiré côté serveur : les messages du serveur sont montrés tels quels', () async {
      final serveur = _Serveur()
        ..erreur = FirebaseFunctionsException(code: 'already-exists', message: 'Ce numéro est déjà validé sur un autre compte Sprint.');
      final passerelle = _Passerelle();
      final service = ValidationTelephone(passerelle: passerelle, appel: serveur.appeler);
      final e = await _refus(service.confirmerCode(const EnvoiSms(identifiant: 'v'), '123456'));
      expect(e.message, 'Ce numéro est déjà validé sur un autre compte Sprint.');
      await Future<void>.delayed(Duration.zero);
      expect(passerelle.terminees, 1, reason: 'la session « téléphone » est fermée même en cas de refus');

      serveur.erreur = FirebaseFunctionsException(code: 'unavailable', message: 'interne');
      final panne = await _refus(service.confirmerCode(const EnvoiSms(identifiant: 'v'), '123456'));
      expect(panne.message, contains('Vérifiez votre connexion'));
    });

    test('messages de Firebase Phone Auth : en français, sans jargon, et les réglages manquants ne sont pas détaillés', () {
      String message(String code) => erreurTelephone(FirebaseAuthException(code: code)).message;
      expect(message('invalid-phone-number'), contains('pas valide'));
      expect(message('too-many-requests'), contains('Trop de demandes'));
      expect(message('quota-exceeded'), contains('saturé'));
      expect(message('code-expired'), contains('expiré'));
      expect(message('network-request-failed'), contains('connexion'));
      for (final reglage in ['operation-not-allowed', 'app-not-authorized', 'missing-client-identifier', 'internal-error', 'autre']) {
        expect(message(reglage), "L'envoi du code est momentanément indisponible. Réessayez plus tard.", reason: reglage);
      }
    });
  });

  group('Écran « Validez votre numéro »', () {
    late _Passerelle passerelle;
    late _Serveur serveur;
    late ValidationTelephone service;
    late List<String> numerosEnregistres;
    late int valide;
    late int plusTard;
    late int deconnexions;

    Future<void> ouvrir(
      WidgetTester tester, {
      String numero = '77 123 45 67',
      bool facultatif = false,
      Duration delaiRenvoi = const Duration(seconds: 60),
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      passerelle = _Passerelle();
      serveur = _Serveur();
      service = ValidationTelephone(passerelle: passerelle, appel: serveur.appeler);
      numerosEnregistres = [];
      valide = 0;
      plusTard = 0;
      deconnexions = 0;
      await tester.pumpWidget(MaterialApp(
        home: ValidationTelephonePage(
          numeroInitial: numero,
          service: service,
          surValide: () => valide++,
          surDeconnexion: () => deconnexions++,
          enregistrerNumero: (n) async => numerosEnregistres.add(n),
          surPlusTard: facultatif ? () => plusTard++ : null,
          delaiRenvoi: delaiRenvoi,
        ),
      ));
      await tester.pump();
    }

    Future<void> envoyerLeCode(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('tel-envoyer')));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('le numéro de l\'inscription est présenté lisiblement, avec « Modifier » ; rien n\'est envoyé tant qu\'on n\'a pas appuyé', (tester) async {
      await ouvrir(tester);
      expect(find.text('Validez votre numéro'), findsOneWidget);
      expect(find.text('+221 77 123 45 67'), findsOneWidget);
      expect(find.byKey(const ValueKey('tel-modifier')), findsOneWidget);
      expect(find.byKey(const ValueKey('tel-plus-tard')), findsNothing, reason: 'obligatoire : pas de « Plus tard »');
      expect(passerelle.envois, isEmpty);
    });

    testWidgets('envoi du code, saisie des 6 chiffres : validé sur le dernier chiffre, le serveur reçoit la preuve', (tester) async {
      await ouvrir(tester);
      await envoyerLeCode(tester);

      expect(passerelle.envois.single.numero, '+221771234567');
      expect(find.text('Entrez le code reçu'), findsOneWidget);
      expect(find.textContaining('+221 77 123 45 67'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.descendant(of: find.byKey(const ValueKey('tel-valider')), matching: find.byType(ElevatedButton))).onPressed, isNull,
          reason: '« Valider » attend les 6 chiffres');

      await tester.enterText(find.byKey(const ValueKey('tel-code')), '12345');
      await tester.pump();
      expect(valide, 0);
      await tester.enterText(find.byKey(const ValueKey('tel-code')), '123456');
      await tester.pump();
      await tester.pump();

      expect(passerelle.confirmations, ['verif-1:123456']);
      expect(serveur.appels.single.donnees, {'jeton': 'jeton-telephone-123456'});
      expect(valide, 1);
    });

    testWidgets('le champ n\'accepte que des chiffres, 6 au plus', (tester) async {
      await ouvrir(tester);
      await envoyerLeCode(tester);
      await tester.enterText(find.byKey(const ValueKey('tel-code')), '12ab34-5678');
      await tester.pump();
      final champ = find.descendant(of: find.byKey(const ValueKey('tel-code')), matching: find.byType(TextField));
      expect(tester.widget<TextField>(champ).controller!.text, '123456');
    });

    testWidgets('mauvais code : message sous le champ, on peut corriger et recommencer', (tester) async {
      await ouvrir(tester);
      await envoyerLeCode(tester);
      passerelle.erreurConfirmation = erreurTelephone(FirebaseAuthException(code: 'invalid-verification-code'));
      await tester.enterText(find.byKey(const ValueKey('tel-code')), '000000');
      await tester.pump();
      await tester.pump();

      expect(find.text('Code incorrect. Vérifiez-le et réessayez.'), findsOneWidget);
      expect(valide, 0);
      expect(serveur.appels, isEmpty);

      passerelle.erreurConfirmation = null;
      await tester.enterText(find.byKey(const ValueKey('tel-code')), '123456');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('tel-erreur')), findsNothing);
      expect(valide, 1);
    });

    testWidgets('numéro refusé par le serveur (déjà pris) : son message est affiché, l\'écran reste ouvert', (tester) async {
      await ouvrir(tester);
      await envoyerLeCode(tester);
      serveur.erreur = FirebaseFunctionsException(code: 'already-exists', message: 'Ce numéro est déjà validé sur un autre compte Sprint.');
      await tester.enterText(find.byKey(const ValueKey('tel-code')), '123456');
      await tester.pump();
      await tester.pump();
      expect(find.text('Ce numéro est déjà validé sur un autre compte Sprint.'), findsOneWidget);
      expect(valide, 0);
    });

    testWidgets('envoi impossible (réglages de la console, quota) : message neutre, on peut réessayer', (tester) async {
      await ouvrir(tester);
      passerelle.erreurEnvoi = erreurTelephone(FirebaseAuthException(code: 'operation-not-allowed'));
      await envoyerLeCode(tester);
      expect(find.text("L'envoi du code est momentanément indisponible. Réessayez plus tard."), findsOneWidget);
      expect(find.text('Validez votre numéro'), findsOneWidget);

      passerelle.erreurEnvoi = null;
      await envoyerLeCode(tester);
      expect(find.text('Entrez le code reçu'), findsOneWidget);
    });

    testWidgets('numéro corrigé : le profil prend le nouveau numéro AVANT l\'envoi, une seule fois', (tester) async {
      await ouvrir(tester);
      await tester.tap(find.byKey(const ValueKey('tel-modifier')));
      await tester.pump();
      // Le champ propose le numéro actuel : la personne le corrige.
      final champ = find.descendant(of: find.byKey(const ValueKey('tel-numero')), matching: find.byType(TextField));
      expect(tester.widget<TextField>(champ).controller!.text, '77 123 45 67');
      await tester.enterText(find.byKey(const ValueKey('tel-numero')), '76 234 56 78');
      await envoyerLeCode(tester);

      expect(numerosEnregistres, ['76 234 56 78']);
      expect(passerelle.envois.single.numero, '+221762345678');
      expect(find.textContaining('+221 76 234 56 78'), findsOneWidget);

      // « Changer de numéro » puis le même numéro : rien à réenregistrer.
      await tester.tap(find.text('Changer de numéro'));
      await tester.pump();
      await envoyerLeCode(tester);
      expect(numerosEnregistres, hasLength(1));
    });

    testWidgets('numéro d\'inscription illisible : la personne le saisit d\'emblée ; un numéro étranger est refusé sans envoi', (tester) async {
      await ouvrir(tester, numero: 'pas un numéro');
      expect(find.byKey(const ValueKey('tel-numero')), findsOneWidget);
      await envoyerLeCode(tester);
      expect(find.textContaining('Sénégal'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('tel-numero')), '+33 6 12 34 56 78');
      await envoyerLeCode(tester);
      expect(passerelle.envois, isEmpty);
      expect(numerosEnregistres, isEmpty);
    });

    testWidgets('renvoi du code : délai de 60 s, puis 3 renvois au plus (chaque SMS est facturé)', (tester) async {
      await ouvrir(tester);
      await envoyerLeCode(tester);
      expect(find.text('Renvoyer le code (60 s)'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.descendant(of: find.byKey(const ValueKey('tel-renvoyer')), matching: find.byType(ElevatedButton))).onPressed, isNull);

      await tester.pump(const Duration(seconds: 59));
      expect(find.text('Renvoyer le code (1 s)'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Renvoyer le code'), findsOneWidget);

      for (var i = 1; i <= 3; i++) {
        await tester.tap(find.byKey(const ValueKey('tel-renvoyer')));
        await tester.pump();
        await tester.pump();
        expect(passerelle.envois, hasLength(1 + i));
        expect(passerelle.envois.last.precedent, isNotNull, reason: 'le renvoi réutilise le jeton de renvoi');
        await tester.pump(const Duration(seconds: 60));
      }
      expect(find.text('Trop de renvois : réessayez plus tard'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tel-renvoyer')), warnIfMissed: false);
      await tester.pump();
      expect(passerelle.envois, hasLength(4));
    });

    testWidgets('Android : le SMS lu automatiquement valide sans saisie', (tester) async {
      await ouvrir(tester);
      await envoyerLeCode(tester);
      passerelle.verificationAutomatique!('jeton-automatique');
      await tester.pump();
      await tester.pump();
      expect(serveur.appels.single.donnees, {'jeton': 'jeton-automatique'});
      expect(valide, 1);
    });

    testWidgets('« Plus tard » n\'existe que si la validation est facultative ; « Se déconnecter » toujours', (tester) async {
      await ouvrir(tester, facultatif: true);
      await tester.tap(find.byKey(const ValueKey('tel-plus-tard')));
      expect(plusTard, 1);
      await tester.tap(find.text('Se déconnecter'));
      expect(deconnexions, 1);
      expect(valide, 0);
    });

    testWidgets('quitter l\'écran avant la fin ferme la session « téléphone » ; la quitter après la réussite ne la ferme pas deux fois', (tester) async {
      await ouvrir(tester);
      await envoyerLeCode(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(passerelle.terminees, 1);
    });
  });
}
