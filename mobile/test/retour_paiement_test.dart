import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/notifications/capacites_navigateur.dart';
import 'package:sprint/core/paiement/retour_operateur.dart';
import 'package:sprint/core/router/app_router.dart';
import 'package:sprint/core/widgets/primary_button.dart';
import 'package:sprint/features/client/presentation/retour_paiement_page.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/portefeuille/data/portefeuille_service.dart';

const _commande = '41b5aaaabbbbccccddddeeee';
const _recharge = 'rch_0123456789abcdef01234567';

void main() {
  group('Retour de Max It (paiement Orange Money)', () {
    test('adresse du site : seul le chemin de retour devient l\'adresse de départ, avec ses paramètres', () {
      expect(
        emplacementRetourPaiement(Uri.parse('https://sprint-vtc.web.app/paiement/retour?ref=$_commande&etat=ok')),
        '/paiement/retour?ref=$_commande&etat=ok',
      );
      expect(emplacementRetourPaiement(Uri.parse('https://sprint-vtc.web.app/paiement/retour')), '/paiement/retour');
      expect(emplacementRetourPaiement(Uri.parse('https://sprint-vtc.web.app/')), isNull);
      expect(emplacementRetourPaiement(Uri.parse('https://sprint-vtc.web.app/#/accueil')), isNull);
      expect(emplacementRetourPaiement(Uri.parse('https://sprint-vtc.web.app/paiement/retour-autre')), isNull);
    });

    test('référence : course (24 hexadécimaux), recharge (« rch_… »), sinon rien', () {
      expect(sortePaiement(_commande), SortePaiement.course);
      expect(sortePaiement(_recharge), SortePaiement.recharge);
      for (final autre in [null, '', 'rch_', '41B5AAAABBBBCCCCDDDDEEEE', '../commandes', 'essai-sprint-1']) {
        expect(sortePaiement(autre), isNull, reason: '$autre');
      }
    });

    Future<void> ouvrir(WidgetTester tester, RetourPaiementPage page) async {
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pump();
    }

    testWidgets('paiement annulé dans Max It : rien n\'est suivi, aucun débit annoncé', (tester) async {
      var sessions = 0;
      await ouvrir(
        tester,
        RetourPaiementPage(reference: _commande, etat: 'annule', sessionConnectee: () async => '${sessions++}'),
      );
      expect(find.text('Paiement annulé'), findsOneWidget);
      expect(find.textContaining("Aucune somme n'a été débitée"), findsOneWidget);
      expect(sessions, 0);
    });

    testWidgets('sans session sur cet appareil (iPhone, Safari) : inviter à revenir dans Sprint', (tester) async {
      await ouvrir(tester, RetourPaiementPage(reference: _commande, etat: 'ok', sessionConnectee: () async => null));
      expect(find.text('Paiement transmis à Orange Money'), findsOneWidget);
      expect(find.text('Ouvrir Sprint'), findsOneWidget);
    });

    group('sans session sur cet appareil : ce que dit la page selon le téléphone', () {
      const iphone = CapacitesNavigateur(iphone: true);
      const iphoneInstalle = CapacitesNavigateur(iphone: true, ecranAccueil: true);
      const android = CapacitesNavigateur(android: true);
      const androidIntegre = CapacitesNavigateur(android: true, vueIntegree: true);

      RetourPaiementPage page(CapacitesNavigateur c, {String? reference = _commande, String etat = 'ok', bool absente = false, Future<bool> Function(Uri)? ouvrirLien}) =>
          RetourPaiementPage(
            reference: reference,
            etat: etat,
            applicationAbsente: absente,
            capacites: () => c,
            ouvrirLien: ouvrirLien,
            sessionConnectee: () async => null,
          );

      testWidgets('iPhone (Safari ou site installé) : ouvrir Sprint depuis son icône, aucun bouton qui resterait dans Safari',
          (tester) async {
        for (final c in [iphone, iphoneInstalle]) {
          await ouvrir(tester, RetourPaiementPage(key: UniqueKey(), reference: _commande, etat: 'ok', capacites: () => c, sessionConnectee: () async => null));
          expect(find.text('Paiement transmis à Orange Money'), findsOneWidget);
          expect(find.textContaining('ouvrez Sprint depuis l\'icône de votre écran d\'accueil'), findsOneWidget);
          expect(find.byType(PrimaryButton), findsNothing);
          expect(find.text('Ouvrir Sprint'), findsNothing);
        }
      });

      testWidgets('Android dans un navigateur : bouton qui rouvre l\'application Sprint sur cette page', (tester) async {
        final ouverts = <Uri>[];
        await ouvrir(tester, page(android, ouvrirLien: (l) async { ouverts.add(l); return true; }));
        expect(find.textContaining('Ouvrez l\'application Sprint'), findsOneWidget);
        await tester.tap(find.text('Ouvrir l\'application Sprint'));
        expect(ouverts, [lienRetourDansLApplication(reference: _commande, etat: 'ok')]);
        final lien = ouverts.single.toString();
        expect(lien, startsWith('intent://sprint-vtc.web.app/paiement/retour?ref=$_commande&etat=ok#Intent;'));
        expect(lien, contains('package=sn.groupesantine.sprint'));
        // Sans l'application : la page revient avec app=0 (elle ne réessaie pas).
        expect(lien, contains('app%3D0'));
      });

      testWidgets('Android sans l\'application (page rouverte avec app=0) : proposer de la télécharger', (tester) async {
        final ouverts = <Uri>[];
        await ouvrir(tester, page(android, absente: true, ouvrirLien: (l) async { ouverts.add(l); return true; }));
        expect(find.textContaining('n\'est pas installée sur ce téléphone'), findsOneWidget);
        expect(find.text('Ouvrir l\'application Sprint'), findsNothing);
        await tester.tap(find.text('Télécharger l\'application'));
        expect(ouverts, [Uri.parse('https://sprint-vtc.web.app/android/')]);
      });

      testWidgets('Android, vue web intégrée à une autre application, ou référence inattendue : comme avant (« Ouvrir Sprint »)',
          (tester) async {
        await ouvrir(tester, page(androidIntegre));
        expect(find.text('Ouvrir Sprint'), findsOneWidget);
        expect(find.text('Ouvrir l\'application Sprint'), findsNothing);
        await ouvrir(tester, RetourPaiementPage(key: UniqueKey(), reference: 'essai-sprint-1', etat: 'ok', capacites: () => android, sessionConnectee: () async => null));
        expect(find.text('Ouvrir Sprint'), findsOneWidget);
      });

      testWidgets('ouverture qui échoue : la page reste affichée, sans erreur', (tester) async {
        await ouvrir(tester, page(android, ouvrirLien: (_) async => throw StateError('refusé')));
        await tester.tap(find.text('Ouvrir l\'application Sprint'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Paiement transmis à Orange Money'), findsOneWidget);
      });

      testWidgets('avec la session (le plus courant) : la page suit le paiement, quel que soit le téléphone', (tester) async {
        final commande = StreamController<CommandePaiement?>();
        await ouvrir(
          tester,
          RetourPaiementPage(
            reference: _commande,
            etat: 'ok',
            capacites: () => iphoneInstalle,
            sessionConnectee: () async => 'awa',
            suivreCommande: (_) => commande.stream,
          ),
        );
        commande.add(const CommandePaiement(statut: StatutCommande.enAttente));
        await tester.pump();
        expect(find.text('Paiement reçu, confirmation en cours…'), findsOneWidget);
        unawaited(commande.close());
      });
    });

    testWidgets('course : attente de la confirmation du serveur, puis suivi de la course ouvert', (tester) async {
      final commande = StreamController<CommandePaiement?>();
      final ouvertes = <String>[];
      await ouvrir(
        tester,
        RetourPaiementPage(
          reference: _commande,
          etat: 'ok',
          sessionConnectee: () async => 'awa',
          suivreCommande: (id) {
            expect(id, _commande);
            return commande.stream;
          },
          ouvrirSuivi: (_, courseId) => ouvertes.add(courseId),
        ),
      );
      commande.add(const CommandePaiement(statut: StatutCommande.enAttente));
      await tester.pump();
      expect(find.text('Paiement reçu, confirmation en cours…'), findsOneWidget);
      expect(find.textContaining('Ne payez pas une seconde fois'), findsOneWidget);
      commande.add(const CommandePaiement(statut: StatutCommande.payee, courseId: 'course-1'));
      await tester.pump();
      expect(find.text('Paiement confirmé'), findsOneWidget);
      expect(ouvertes, ['course-1']);
      await tester.tap(find.text('Suivre ma course'));
      expect(ouvertes, ['course-1', 'course-1']);
      unawaited(commande.close());
    });

    testWidgets('recharge : créditée par le serveur, sinon refusée', (tester) async {
      await ouvrir(
        tester,
        RetourPaiementPage(
          reference: _recharge,
          etat: 'ok',
          sessionConnectee: () async => 'awa',
          suivreRecharge: (_) => Stream.value(const AvancementRecharge(statut: StatutRecharge.reussie)),
        ),
      );
      await tester.pump();
      expect(find.text('Recharge effectuée'), findsOneWidget);
      expect(find.text('Voir mon portefeuille'), findsOneWidget);

      await tester.pumpWidget(MaterialApp(
        home: RetourPaiementPage(
          key: UniqueKey(),
          reference: _commande,
          etat: 'ok',
          sessionConnectee: () async => 'awa',
          suivreCommande: (_) => Stream.value(const CommandePaiement(statut: StatutCommande.echouee)),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Paiement non abouti'), findsOneWidget);
      expect(find.textContaining("Aucune course n'a été créée"), findsOneWidget);
    });

    testWidgets('confirmation trop longue : la page cesse d\'attendre et renvoie vers Activité', (tester) async {
      final commande = StreamController<CommandePaiement?>();
      await ouvrir(
        tester,
        RetourPaiementPage(
          reference: _commande,
          etat: 'ok',
          sessionConnectee: () async => 'awa',
          suivreCommande: (_) => commande.stream,
          delaiMax: const Duration(seconds: 5),
        ),
      );
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('Confirmation plus longue que prévu'), findsOneWidget);
      expect(find.text('Voir mes courses'), findsOneWidget);
      unawaited(commande.close());
    });

    testWidgets('lecture refusée (pas le compte de cette commande) : inviter à revenir dans Sprint', (tester) async {
      await ouvrir(
        tester,
        RetourPaiementPage(
          reference: _commande,
          etat: 'ok',
          sessionConnectee: () async => 'awa',
          suivreCommande: (_) => Stream.error(Exception('permission-denied')),
        ),
      );
      await tester.pump();
      expect(find.text('Paiement transmis à Orange Money'), findsOneWidget);
    });
  });

  group('Retour après paiement : ce qui est lu dans les fichiers du projet', () {
    test('la bannière « Installez Sprint » n\'apparaît jamais sur la page de retour de paiement', () {
      final index = File('web/index.html').readAsStringSync();
      expect(index, contains("location.pathname.indexOf('/paiement/retour') === 0"));
      expect(index, contains('|| retourPaiement) return;'));
    });

    test('demandes de paiement et de recharge : l\'option « sans retour » du téléphone est transmise au serveur', () {
      for (final fichier in [
        'lib/features/courses/data/course_service.dart',
        'lib/features/portefeuille/data/portefeuille_service.dart',
      ]) {
        final source = File(fichier).readAsStringSync();
        expect(source, contains('...optionRetour(),'), reason: fichier);
        expect(source, contains("import '../../../core/paiement/retour_operateur.dart';"), reason: fichier);
      }
    });

    test('le routeur donne app=0 à la page de retour', () {
      expect(
        File('lib/core/router/app_router.dart').readAsStringSync(),
        contains("applicationAbsente: state.uri.queryParameters['app'] == '0'"),
      );
    });

    test('adresse du site et paquet de l\'APK : ceux du manifeste Android et d\'assetlinks.json', () {
      final manifeste = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifeste, contains('android:host="$hoteSprint"'));
      expect(manifeste, contains('android:pathPrefix="$cheminRetourPaiement"'));
      expect(File('hebergement/assetlinks.json').readAsStringSync(), contains('"package_name": "$paquetSprint"'));
      expect(File('functions/src/index.ts').readAsStringSync(), contains('const URL_RETOUR_PAIEMENT = `\${SITE}$cheminRetourPaiement`;'));
    });
  });

  // Fichiers lus depuis mobile/ (dossier des tests) : l'APK ne s'ouvre seul au
  // retour de Max It que si les trois concordent.
  group('Lien d\'application Android (retour de paiement dans l\'APK)', () {
    test('l\'APK capte seulement l\'adresse de retour, avec vérification du site', () {
      final manifeste = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifeste, contains('android:autoVerify="true"'));
      expect(
        manifeste,
        contains('<data android:scheme="https" android:host="sprint-vtc.web.app" android:pathPrefix="/paiement/retour"/>'),
      );
    });

    test('assetlinks.json déclare le paquet Sprint et une empreinte SHA-256', () {
      final declarations = jsonDecode(File('hebergement/assetlinks.json').readAsStringSync()) as List<dynamic>;
      final sprint = declarations.cast<Map<String, dynamic>>().singleWhere(
            (d) => (d['target'] as Map<String, dynamic>)['package_name'] == 'sn.groupesantine.sprint',
          );
      expect(sprint['relation'], contains('delegate_permission/common.handle_all_urls'));
      final empreintes = (sprint['target'] as Map<String, dynamic>)['sha256_cert_fingerprints'] as List<dynamic>;
      // L'empreinte elle-même est comparée à celle de l'APK signé par la publication.
      expect(empreintes, isNotEmpty);
      for (final e in empreintes) {
        expect(e, matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));
      }
    });

    test('Firebase Hosting sert notre fichier (pas celui qu\'il générerait), avant la réécriture vers l\'app', () {
      final hebergement = (jsonDecode(File('firebase.json').readAsStringSync()) as Map<String, dynamic>)['hosting']
          as Map<String, dynamic>;
      // AUTO (défaut) : Firebase remplace le fichier par le sien, sans l'empreinte de l'APK.
      expect(hebergement['appAssociation'], 'NONE');
      final reecritures = (hebergement['rewrites'] as List<dynamic>).cast<Map<String, dynamic>>();
      final lien = reecritures.indexWhere((r) => r['source'] == '/.well-known/assetlinks.json');
      expect(lien, isNot(-1));
      expect(reecritures[lien]['destination'], '/assetlinks.json');
      expect(lien, lessThan(reecritures.indexWhere((r) => r['source'] == '**')));
      expect(File('hebergement/assembler.sh').readAsStringSync(), contains('cp hebergement/assetlinks.json'));
    });
  });
}
