import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/router/app_router.dart';
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
}
