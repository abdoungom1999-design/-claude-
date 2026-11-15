// Porte d'inscription : ce qu'elle laisse passer, ce qu'elle demande, et surtout ce qu'elle ne touche pas.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/auth/data/reglage_inscription.dart';
import 'package:sprint/features/auth/data/validation_telephone.dart';
import 'package:sprint/features/auth/presentation/bienvenue_sprint_page.dart';
import 'package:sprint/features/auth/presentation/porte_inscription.dart';

/// Faux Firebase Phone Auth : le code est toujours accepté.
class _Passerelle implements PasserelleSms {
  int envois = 0;

  @override
  Future<EnvoiSms> envoyer(String numero, {EnvoiSms? precedent, required void Function(String jeton) surVerificationAutomatique}) async {
    envois++;
    return const EnvoiSms(identifiant: 'v1');
  }

  @override
  Future<String> confirmer(EnvoiSms envoi, String code) async => 'jeton-$code';

  @override
  Future<void> terminer() async {}
}

final _ouverture = DateTime.utc(2026, 11, 20, 8);
final _nouveau = DateTime.utc(2026, 11, 20, 9);
final _ancien = DateTime.utc(2026, 11, 19);

const _profilAwa = {
  'role': 'client',
  'nom': 'Awa Ndiaye',
  'email': 'awa@test.sn',
  'telephone': '77 123 45 67',
};

/// Tout ce que la porte pourrait lire ou appeler, compté.
class _Banc {
  CompteConnecte? compte = CompteConnecte(uid: 'awa', emailVerifie: true, creeLe: _nouveau);
  Map<String, dynamic>? profil = {..._profilAwa};
  Object? erreurProfil;
  bool profilSansFin = false;
  Map<String, dynamic> reponseBienvenue = {'envoye': true, 'role': 'client'};
  Object? erreurBienvenue;
  bool bienvenueSansFin = false;

  int lecturesCompte = 0;
  int lecturesProfil = 0;
  int appelsBienvenue = 0;
  final appelsServeur = <String>[];
  final numerosEnregistres = <String>[];
  final passes = <String>{};
  int deconnexions = 0;

  Widget app({ReglageInscription reglage = const ReglageInscription(), Duration delaiReponse = const Duration(seconds: 10)}) {
    final passerelle = _Passerelle();
    return MaterialApp(
      home: PorteInscription(
        enfant: const Text('ESPACE', key: ValueKey('espace')),
        reglage: reglage,
        compteConnecte: () {
          lecturesCompte++;
          return compte;
        },
        lireProfil: (uid) {
          lecturesProfil++;
          if (profilSansFin) return Completer<Map<String, dynamic>?>().future;
          final e = erreurProfil;
          if (e != null) return Future.error(e);
          return Future.value(profil);
        },
        service: ValidationTelephone(
          passerelle: passerelle,
          appel: (nom, donnees) async {
            appelsServeur.add(nom);
            return {'valide': true};
          },
        ),
        declencherBienvenue: () {
          appelsBienvenue++;
          if (bienvenueSansFin) return Completer<Map<String, dynamic>>().future;
          final e = erreurBienvenue;
          if (e != null) return Future.error(e);
          return Future.value(reponseBienvenue);
        },
        enregistrerNumero: (n) async => numerosEnregistres.add(n),
        surDeconnexion: () async => deconnexions++,
        passeAvant: (uid) async => passes.contains(uid),
        retenirPasse: (uid) async => passes.add(uid),
        delaiReponse: delaiReponse,
      ),
    );
  }
}

ReglageInscription _reglage({EtatValidationTelephone validation = EtatValidationTelephone.obligatoire, bool bienvenue = false}) =>
    ReglageInscription(validation: validation, bienvenue: bienvenue, depuis: _ouverture);

Future<void> _laisser(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

Future<void> _ouvrir(WidgetTester tester, _Banc banc, {ReglageInscription? reglage, Duration delaiReponse = const Duration(seconds: 10)}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(banc.app(reglage: reglage ?? _reglage(), delaiReponse: delaiReponse));
  await _laisser(tester);
}

final _espace = find.byKey(const ValueKey('espace'));

/// Envoi du code puis saisie : le parcours de la personne.
Future<void> _validerLeNumero(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('tel-envoyer')));
  await _laisser(tester);
  await tester.enterText(find.byKey(const ValueKey('tel-code')), '123456');
  await _laisser(tester);
}

void main() {
  group('Réglages livrés (publication 128) et retour à l\'état de la 126', () {
    test('réglages livrés : SMS facultatif, bienvenue, comptes neufs depuis l\'ouverture (décisions du client)', () {
      const livre = ReglageInscription();
      expect(livre.validation, EtatValidationTelephone.facultative, reason: 'obligatoire seulement sur demande du client');
      expect(livre.bienvenue, isTrue);
      expect(livre.ouvert, isTrue);
      expect(livre.depuis, DateTime.utc(2026, 11, 15, 19, 28), reason: 'même instant que le serveur (un test les compare)');
      expect(livre.estNouveau(livre.depuis), isTrue);
      expect(livre.estNouveau(livre.depuis.subtract(const Duration(minutes: 1))), isFalse);
      expect(livre.estNouveau(null), isFalse);
    });

    test('un compte est nouveau à l\'instant de l\'ouverture et après, jamais avant ni sans date', () {
      final r = _reglage();
      expect(r.estNouveau(_ouverture), isTrue, reason: 'borne incluse');
      expect(r.estNouveau(_nouveau), isTrue);
      expect(r.estNouveau(_ouverture.subtract(const Duration(milliseconds: 1))), isFalse);
      expect(r.estNouveau(_ancien), isFalse);
      expect(r.estNouveau(null), isFalse);
    });

    testWidgets('refermé (validation fermée, pas de bienvenue) : l\'espace s\'affiche tel quel, sans même regarder le compte ni le profil', (tester) async {
      final banc = _Banc();
      await _ouvrir(tester, banc, reglage: const ReglageInscription(validation: EtatValidationTelephone.fermee, bienvenue: false));
      await tester.pump(const Duration(seconds: 30));
      expect(_espace, findsOneWidget);
      expect(banc.lecturesCompte, 0);
      expect(banc.lecturesProfil, 0);
      expect(banc.appelsBienvenue, 0);
      expect(banc.appelsServeur, isEmpty);
    });

    test('le routeur enveloppe les deux espaces dans la porte, et rien d\'autre', () {
      final routeur = File('lib/core/router/app_router.dart').readAsStringSync();
      expect(routeur, contains('PorteInscription(enfant: HomeShellPage(navigationShell: navigationShell))'));
      expect(routeur, contains('const PorteInscription(enfant: ConducteurShellPage())'));
      expect(RegExp('PorteInscription\\(').allMatches(routeur).length, 2);
    });

    test('la porte et ses écrans ne touchent ni aux paiements, ni aux recharges, ni aux retraits, ni aux comptes de test', () {
      for (final fichier in [
        'lib/features/auth/presentation/porte_inscription.dart',
        'lib/features/auth/presentation/validation_telephone_page.dart',
        'lib/features/auth/presentation/bienvenue_sprint_page.dart',
        'lib/features/auth/data/validation_telephone.dart',
        'lib/features/auth/data/reglage_inscription.dart',
      ]) {
        final source = File(fichier).readAsStringSync();
        for (final interdit in ['testeurOrangeMoney', 'argentDeTest', 'soldeFcfa', 'creerPaiement', 'creerRecharge', 'demanderRetrait', 'payment_method', 'paiement_orange']) {
          expect(source, isNot(contains(interdit)), reason: '$fichier mentionne $interdit');
        }
      }
    });
  });

  group('Ouvert : qui est concerné', () {
    testWidgets('un compte créé avant l\'ouverture n\'est ni sollicité ni lu, et rien ne tourne en arrière-plan', (tester) async {
      final banc = _Banc()..compte = CompteConnecte(uid: 'ancien', emailVerifie: true, creeLe: _ancien);
      await _ouvrir(tester, banc);
      await tester.pump(const Duration(seconds: 30));
      expect(_espace, findsOneWidget);
      expect(banc.lecturesProfil, 0);
      expect(banc.appelsBienvenue, 0);
      expect(banc.lecturesCompte, 1, reason: 'une seule lecture : pas de surveillance');
    });

    testWidgets('réglages LIVRÉS : un compte antérieur à l\'ouverture ne voit rien de nouveau (ni écran, ni lecture du profil, ni bienvenue)', (tester) async {
      const livre = ReglageInscription();
      final banc = _Banc()..compte = CompteConnecte(uid: 'ancien', emailVerifie: true, creeLe: livre.depuis.subtract(const Duration(minutes: 1)));
      await _ouvrir(tester, banc, reglage: livre);
      await tester.pump(const Duration(seconds: 30));
      expect(_espace, findsOneWidget);
      expect(banc.lecturesProfil, 0);
      expect(banc.appelsBienvenue, 0);
      expect(banc.appelsServeur, isEmpty);
    });

    testWidgets('réglages LIVRÉS : un compte neuf voit « Plus tard » (SMS facultatif), puis « Bienvenue chez SPRINT », puis son espace', (tester) async {
      const livre = ReglageInscription();
      final banc = _Banc()..compte = CompteConnecte(uid: 'awa', emailVerifie: true, creeLe: livre.depuis);
      await _ouvrir(tester, banc, reglage: livre);
      expect(find.text('Validez votre numéro'), findsOneWidget);
      expect(find.byKey(const ValueKey('tel-plus-tard')), findsOneWidget);
      expect(_espace, findsNothing);

      await tester.tap(find.byKey(const ValueKey('tel-plus-tard')));
      await _laisser(tester);
      expect(banc.passes, {'awa'});
      expect(banc.appelsBienvenue, 1);
      expect(find.text('Bienvenue chez SPRINT'), findsOneWidget);
      expect(find.text('Bonjour Awa, votre compte SPRINT est prêt.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('bienvenue-continuer')));
      await _laisser(tester);
      expect(_espace, findsOneWidget);
      expect(banc.appelsServeur, isEmpty, reason: 'numéro passé : aucun SMS, aucune validation');
    });

    testWidgets('sans connexion, ou sans date de création connue : l\'espace', (tester) async {
      final banc = _Banc()..compte = null;
      await _ouvrir(tester, banc);
      expect(_espace, findsOneWidget);
      banc.compte = const CompteConnecte(uid: 'x', emailVerifie: true, creeLe: null);
      await tester.pumpWidget(banc.app(reglage: _reglage()));
      await _laisser(tester);
      expect(_espace, findsOneWidget);
      expect(banc.lecturesProfil, 0);
    });

    testWidgets('nouveau compte à l\'e-mail non vérifié : l\'espace (son écran « vérifiez votre e-mail »), puis la porte dès que l\'e-mail l\'est', (tester) async {
      final banc = _Banc()..compte = CompteConnecte(uid: 'awa', emailVerifie: false, creeLe: _nouveau);
      await _ouvrir(tester, banc);
      expect(_espace, findsOneWidget);
      expect(banc.lecturesProfil, 0, reason: 'rien n\'est lu avant la vérification');

      await tester.pump(const Duration(seconds: 3));
      expect(_espace, findsOneWidget);
      banc.compte = CompteConnecte(uid: 'awa', emailVerifie: true, creeLe: _nouveau);
      await tester.pump(const Duration(seconds: 3));
      await _laisser(tester);

      expect(find.text('Validez votre numéro'), findsOneWidget);
      expect(_espace, findsNothing);
      expect(banc.lecturesProfil, 1);
    });
  });

  group('Validation du numéro', () {
    testWidgets('obligatoire : un nouveau compte dont le numéro n\'est pas validé voit l\'écran, pas l\'espace', (tester) async {
      final banc = _Banc();
      await _ouvrir(tester, banc);
      expect(find.text('Validez votre numéro'), findsOneWidget);
      expect(find.text('+221 77 123 45 67'), findsOneWidget);
      expect(_espace, findsNothing);
      expect(find.byKey(const ValueKey('tel-plus-tard')), findsNothing);
    });

    testWidgets('code juste : le serveur est appelé, l\'espace s\'ouvre (bienvenue fermée : rien d\'autre)', (tester) async {
      final banc = _Banc();
      await _ouvrir(tester, banc);
      await _validerLeNumero(tester);
      expect(banc.appelsServeur, ['validerTelephone']);
      expect(_espace, findsOneWidget);
      expect(banc.appelsBienvenue, 0);
    });

    testWidgets('numéro déjà validé (et toujours le même) : pas d\'écran', (tester) async {
      final banc = _Banc()..profil = {..._profilAwa, 'telephoneVerifie': true, 'telephoneValide': '+221771234567'};
      await _ouvrir(tester, banc);
      expect(_espace, findsOneWidget);
      expect(banc.appelsServeur, isEmpty);
    });

    testWidgets('numéro modifié depuis sa validation : à valider de nouveau', (tester) async {
      final banc = _Banc()..profil = {..._profilAwa, 'telephone': '76 234 56 78', 'telephoneVerifie': true, 'telephoneValide': '+221771234567'};
      await _ouvrir(tester, banc);
      expect(find.text('Validez votre numéro'), findsOneWidget);
    });

    testWidgets('facultative : « Plus tard » ouvre l\'espace et s\'en souvient ; l\'écran ne revient pas', (tester) async {
      final banc = _Banc();
      final facultative = _reglage(validation: EtatValidationTelephone.facultative);
      await _ouvrir(tester, banc, reglage: facultative);
      expect(find.text('Validez votre numéro'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tel-plus-tard')));
      await _laisser(tester);
      expect(_espace, findsOneWidget);
      expect(banc.passes, {'awa'});

      await tester.pumpWidget(const SizedBox());
      await _ouvrir(tester, banc, reglage: facultative);
      expect(_espace, findsOneWidget, reason: 'déjà passé sur cet appareil');
    });

    testWidgets('obligatoire : un « Plus tard » ancien (période facultative) ne dispense plus', (tester) async {
      final banc = _Banc()..passes.add('awa');
      await _ouvrir(tester, banc);
      expect(find.text('Validez votre numéro'), findsOneWidget);
      expect(_espace, findsNothing);
    });

    testWidgets('« Se déconnecter » est toujours possible', (tester) async {
      final banc = _Banc();
      await _ouvrir(tester, banc);
      await tester.tap(find.text('Se déconnecter'));
      expect(banc.deconnexions, 1);
    });

    testWidgets('numéro corrigé sur l\'écran : le profil est mis à jour avant l\'envoi du code', (tester) async {
      final banc = _Banc();
      await _ouvrir(tester, banc);
      await tester.tap(find.byKey(const ValueKey('tel-modifier')));
      await tester.pump();
      await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('tel-numero')), matching: find.byType(TextField)),
        '76 234 56 78',
      );
      await tester.tap(find.byKey(const ValueKey('tel-envoyer')));
      await _laisser(tester);
      expect(banc.numerosEnregistres, ['76 234 56 78']);
    });
  });

  group('Quand quelque chose échoue, la personne n\'est jamais enfermée dehors', () {
    testWidgets('profil illisible, absent, rôle sans espace (Admin) ou trop lent : l\'espace', (tester) async {
      final banc = _Banc()..erreurProfil = StateError('réseau');
      await _ouvrir(tester, banc);
      expect(_espace, findsOneWidget);

      banc
        ..erreurProfil = null
        ..profil = null;
      await tester.pumpWidget(const SizedBox());
      await _ouvrir(tester, banc);
      expect(_espace, findsOneWidget);

      banc.profil = {..._profilAwa, 'role': 'admin'};
      await tester.pumpWidget(const SizedBox());
      await _ouvrir(tester, banc);
      expect(_espace, findsOneWidget);

      banc
        ..profil = {..._profilAwa}
        ..profilSansFin = true;
      await tester.pumpWidget(const SizedBox());
      await _ouvrir(tester, banc, delaiReponse: const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 100));
      await _laisser(tester);
      expect(_espace, findsOneWidget);
      expect(banc.appelsServeur, isEmpty);
    });
  });

  group('« Bienvenue chez SPRINT »', () {
    testWidgets('numéro non demandé (fermé) mais bienvenue ouverte : écran de bienvenue une fois, puis l\'espace', (tester) async {
      final banc = _Banc();
      await _ouvrir(tester, banc, reglage: _reglage(validation: EtatValidationTelephone.fermee, bienvenue: true));
      expect(banc.appelsBienvenue, 1);
      expect(find.text('Bienvenue chez SPRINT'), findsOneWidget);
      expect(find.text('Bonjour Awa, votre compte SPRINT est prêt.'), findsOneWidget);
      expect(_espace, findsNothing);
      await tester.tap(find.byKey(const ValueKey('bienvenue-continuer')));
      await _laisser(tester);
      expect(_espace, findsOneWidget);
      expect(find.text('Bienvenue chez SPRINT'), findsNothing);
      expect(banc.appelsBienvenue, 1);
    });

    testWidgets('après la validation du numéro : bienvenue, puis l\'espace', (tester) async {
      final banc = _Banc();
      await _ouvrir(tester, banc, reglage: _reglage(bienvenue: true));
      expect(banc.appelsBienvenue, 0, reason: 'pas avant la validation du numéro');
      await _validerLeNumero(tester);
      expect(banc.appelsBienvenue, 1);
      expect(find.text('Bienvenue chez SPRINT'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bienvenue-continuer')));
      await _laisser(tester);
      expect(_espace, findsOneWidget);
    });

    testWidgets('chauffeur : texte du chauffeur', (tester) async {
      final banc = _Banc()..profil = {..._profilAwa, 'role': 'conducteur', 'prenom': 'Moussa', 'nom': 'Moussa Diop'};
      banc.reponseBienvenue = {'envoye': true, 'role': 'conducteur'};
      await _ouvrir(tester, banc, reglage: _reglage(validation: EtatValidationTelephone.fermee, bienvenue: true));
      expect(find.text("Bonjour Moussa, bienvenue dans l'équipe SPRINT."), findsOneWidget);
      expect(find.text('Compléter mon dossier'), findsOneWidget);
    });

    testWidgets('déjà accueilli, ou le serveur dit non, ou panne, ou lenteur : l\'espace, sans écran', (tester) async {
      final reglage = _reglage(validation: EtatValidationTelephone.fermee, bienvenue: true);

      final accueilli = _Banc()..profil = {..._profilAwa, 'bienvenueEnvoyeeLe': 'déjà'};
      await _ouvrir(tester, accueilli, reglage: reglage);
      expect(_espace, findsOneWidget);
      expect(accueilli.appelsBienvenue, 0, reason: 'inutile de demander au serveur');

      final refus = _Banc()..reponseBienvenue = {'envoye': false, 'raison': 'deja_envoye'};
      await tester.pumpWidget(const SizedBox());
      await _ouvrir(tester, refus, reglage: reglage);
      expect(_espace, findsOneWidget);
      expect(refus.appelsBienvenue, 1);

      final panne = _Banc()..erreurBienvenue = StateError('serveur');
      await tester.pumpWidget(const SizedBox());
      await _ouvrir(tester, panne, reglage: reglage);
      expect(_espace, findsOneWidget);

      final lent = _Banc()..bienvenueSansFin = true;
      await tester.pumpWidget(const SizedBox());
      await _ouvrir(tester, lent, reglage: reglage, delaiReponse: const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 100));
      await _laisser(tester);
      expect(_espace, findsOneWidget);
    });

    test('prénom : celui du profil, sinon le premier mot du nom, sans caractère dangereux', () {
      expect(prenomPour({'prenom': 'Moussa', 'nom': 'Moussa Diop'}), 'Moussa');
      expect(prenomPour({'nom': '  Awa   Ndiaye '}), 'Awa');
      expect(prenomPour({'nom': '<b>Awa</b> Fall'}), isNot(contains('<')));
      expect(prenomPour({'nom': 'A' * 100}), hasLength(40));
      expect(prenomPour({}), '');
      expect(prenomPour(null), '');
    });

    test('texte : même salutation avec ou sans prénom', () {
      expect(messageBienvenue('client', 'Awa').accroche, 'Bonjour Awa, votre compte SPRINT est prêt.');
      expect(messageBienvenue('client', '').accroche, 'Bonjour, votre compte SPRINT est prêt.');
      expect(messageBienvenue('conducteur', '').accroche, "Bonjour, bienvenue dans l'équipe SPRINT.");
      expect(messageBienvenue('client', 'Awa').titre, 'Bienvenue chez SPRINT');
    });
  });
}
