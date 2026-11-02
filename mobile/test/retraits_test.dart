import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/network/api_exception.dart';
import 'package:sprint/core/utils/format_fcfa.dart';
import 'package:sprint/core/widgets/primary_button.dart';
import 'package:sprint/core/widgets/wallet_card.dart';
import 'package:sprint/features/admin/presentation/sections/admin_finances_section.dart';
import 'package:sprint/features/compte/presentation/compte_tab_page.dart';
import 'package:sprint/features/finances/data/comptabilite.dart';
import 'package:sprint/features/finances/data/finance_service.dart';
import 'package:sprint/features/portefeuille/data/portefeuille_service.dart';
import 'package:sprint/features/portefeuille/data/retraits.dart';

/// Retraits du solde (lot B) : fermés tant que le client n'a pas donné son
/// go ; ouverts ici par injection, pour vérifier l'écran du client et celui
/// de l'Admin.

class _PortefeuilleFactice extends PortefeuilleService {
  _PortefeuilleFactice(this.portefeuille);

  final Portefeuille portefeuille;

  @override
  Stream<Portefeuille> streamPortefeuille(String uid) => Stream.value(portefeuille);

  @override
  Future<void> definirPayerAvecSolde(String uid, bool valeur) async {}
}

class _RetraitsFactices extends RetraitService {
  _RetraitsFactices({this.refus, this.aTraiter = const []});

  final Exception? refus;
  final List<Retrait> aTraiter;
  final enCours = StreamController<Retrait?>.broadcast();
  final demandes = <(int, MoyenRetrait, String)>[];
  final traitements = <({String id, bool verse, String reference, String motif})>[];
  var suivis = 0;

  @override
  Future<int> demander({required int montantFcfa, required MoyenRetrait moyen, required String numero}) async {
    if (refus case final erreur?) throw erreur;
    demandes.add((montantFcfa, moyen, numero));
    return 0;
  }

  @override
  Stream<Retrait?> streamRetraitEnCours(String uid) {
    suivis++;
    return enCours.stream;
  }

  @override
  Stream<List<Retrait>> streamRetraitsATraiter() => Stream.value(aTraiter);

  @override
  Future<void> traiter({required String retraitId, required bool verse, String reference = '', String motif = ''}) async {
    if (refus case final erreur?) throw erreur;
    traitements.add((id: retraitId, verse: verse, reference: reference, motif: motif));
  }
}

class _RetraitsIllisibles extends _RetraitsFactices {
  @override
  Stream<List<Retrait>> streamRetraitsATraiter() => throw StateError('Firebase absent');
}

class _FinancesVides extends FinanceService {
  @override
  Stream<List<LigneCourse>> streamToutesCourses() => Stream.value(const []);

  @override
  Stream<List<Reglement>> streamTousReglements() => Stream.value(const []);
}

const _profil = {'nom': 'Awa Ndiaye', 'telephone': '+221 77 123 45 67'};

final _enAttente = Retrait(
  id: 'rtr_000000000000000000000001',
  clientId: 'awa',
  montantFcfa: 1500,
  moyen: MoyenRetrait.orangeMoney,
  numero: '771234567',
  nomClient: 'Awa Ndiaye',
  numeroDuCompte: true,
  creeLe: DateTime(2026, 11, 2, 12, 5),
);

void main() {
  group('retraits : réglages et numéro', () {
    test('fermés tant que le client n\'a pas donné son go ; mêmes minimum et moyens que le serveur', () {
      expect(retraitsOuverts, isFalse);
      expect(retraitMinFcfa, 500);
      expect([for (final m in MoyenRetrait.values) m.apiValue], ['ORANGE_MONEY', 'WAVE']);
      expect(MoyenRetrait.depuis('WAVE'), MoyenRetrait.wave);
      expect(MoyenRetrait.depuis('PORTEFEUILLE'), isNull);
    });

    // Mêmes cas que functions/test/retraits.test.ts (règle écrite deux fois).
    test('numéro de réception : mobile sénégalais, indicatif et séparateurs acceptés', () {
      const valides = {
        '771234567': '771234567',
        '77 123 45 67': '771234567',
        '77.123.45.67': '771234567',
        '77-123-45-67': '771234567',
        '+221 77 123 45 67': '771234567',
        '+221771234567': '771234567',
        '00221 76 123 45 67': '761234567',
        '221781234567': '781234567',
        '70 123 45 67': '701234567',
        '75 123 45 67': '751234567',
      };
      valides.forEach((saisi, attendu) => expect(numeroSenegal(saisi), attendu, reason: saisi));
      for (final saisi in [
        '',
        '   ',
        '77123456',
        '7712345678',
        '33 823 45 67',
        '+221 33 823 45 67',
        '72 123 45 67',
        '79 123 45 67',
        '+33 6 12 34 56 78',
        '0033612345678',
        '221 33 823 45 67',
        '77 123 45 6a',
        '+22177123456',
        '77_123_45_67',
      ]) {
        expect(numeroSenegal(saisi), isNull, reason: saisi);
      }
      expect(formaterNumero('771234567'), '77 123 45 67');
      expect(formaterNumero('123'), '123');
    });

    test('demande lue depuis Firestore ; libellés des mouvements', () {
      final r = Retrait.depuisDocument('rtr_1', {
        'clientId': 'awa',
        'montantFcfa': 1500,
        'moyen': 'WAVE',
        'numero': '701234567',
        'nomClient': 'Awa',
        'numeroDuCompte': true,
      });
      expect([r.clientId, r.montantFcfa, r.moyen, r.numeroLisible, r.nomClient, r.numeroDuCompte],
          ['awa', 1500, MoyenRetrait.wave, '70 123 45 67', 'Awa', true]);
      final vide = Retrait.depuisDocument('rtr_2', {});
      expect([vide.montantFcfa, vide.moyen, vide.nomClient, vide.numeroDuCompte], [0, null, 'Client', false]);

      MouvementPortefeuille mouvement(String type, int montant, String note) => MouvementPortefeuille(
            id: 'm',
            type: type,
            montantFcfa: montant,
            soldeApresFcfa: 0,
            note: note,
          );
      expect(mouvement(MouvementPortefeuille.retrait, -1500, 'Orange Money').libelle, 'Retrait du solde');
      expect(mouvement(MouvementPortefeuille.retraitRendu, 1500, 'Numéro injoignable').libelle,
          'Retrait refusé : montant rendu');
    });
  });

  group('carte du portefeuille', () {
    Future<void> afficher(WidgetTester tester, {VoidCallback? onRetirer}) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WalletCard(
                soldeFcfa: 5000,
                payerAvecSolde: false,
                onTogglePaiement: (_) {},
                onRecharger: () {},
                onRetirer: onRetirer,
              ),
            ),
          ),
        );

    testWidgets('retraits fermés : seulement « Recharger », comme avant', (tester) async {
      await afficher(tester);
      expect(find.widgetWithText(ElevatedButton, 'Recharger'), findsOneWidget);
      expect(find.byKey(const ValueKey('bouton-retirer')), findsNothing);
      expect(find.text('Retirer'), findsNothing);
    });

    testWidgets('retraits ouverts : « Retirer » à côté de « Recharger »', (tester) async {
      var retire = 0;
      await afficher(tester, onRetirer: () => retire++);
      expect(find.widgetWithText(ElevatedButton, 'Recharger'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bouton-retirer')));
      expect(retire, 1);
    });
  });

  group('onglet Compte : retrait du solde', () {
    Future<_RetraitsFactices> ouvrir(
      WidgetTester tester, {
      bool ouverts = true,
      int solde = 5000,
      _RetraitsFactices? retraits,
    }) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final service = retraits ?? _RetraitsFactices();
      await tester.pumpWidget(
        MaterialApp(
          home: CompteTabPage(
            service: _PortefeuilleFactice(Portefeuille(soldeFcfa: solde)),
            clientId: 'awa',
            profil: Stream.value(_profil),
            retraits: service,
            retraitsDisponibles: ouverts,
          ),
        ),
      );
      await tester.pump();
      return service;
    }

    Future<void> ouvrirFeuille(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('bouton-retirer')));
      await tester.pumpAndSettle();
    }

    final confirmer = find.text('Confirmer le retrait');
    bool actif(WidgetTester tester) =>
        tester.widget<PrimaryButton>(find.ancestor(of: confirmer, matching: find.byType(PrimaryButton))).onPressed !=
        null;

    testWidgets('retraits fermés (réglage en service) : ni bouton, ni bandeau, ni lecture ; texte de recharge inchangé',
        (tester) async {
      final service = await ouvrir(tester, ouverts: false);
      expect(find.byKey(const ValueKey('bouton-retirer')), findsNothing);
      expect(find.byKey(const ValueKey('bandeau-retrait')), findsNothing);
      expect(service.suivis, 0);
      await tester.tap(find.text('Recharger'));
      await tester.pumpAndSettle();
      expect(find.text('Le solde sert uniquement à payer vos courses. Il n\'est pas retirable.'), findsOneWidget);
    });

    testWidgets('feuille : tout le solde et le numéro du compte proposés ; résumé avant confirmation', (tester) async {
      await ouvrir(tester);
      await ouvrirFeuille(tester);
      expect(find.text('Retirer mon solde'), findsOneWidget);
      expect(find.widgetWithText(TextField, '5000'), findsOneWidget);
      expect(find.widgetWithText(TextField, '77 123 45 67'), findsOneWidget);
      expect(
        find.text('Vous recevrez ${formaterFcfa(5000)} sur le 77 123 45 67 (Orange Money).'),
        findsOneWidget,
      );
      expect(actif(tester), isTrue);
    });

    testWidgets('demande : montant, Wave et numéro envoyés au serveur ; confirmation au client', (tester) async {
      final service = await ouvrir(tester);
      await ouvrirFeuille(tester);
      await tester.enterText(find.byKey(const ValueKey('montant-retrait')), '1500');
      await tester.tap(find.byKey(const ValueKey('moyen-retrait-WAVE')));
      await tester.enterText(find.byKey(const ValueKey('numero-retrait')), '+221 70 123 45 67');
      await tester.pump();
      expect(find.text('Numéro Wave'), findsOneWidget);
      expect(find.text('Vous recevrez ${formaterFcfa(1500)} sur le 70 123 45 67 (Wave).'), findsOneWidget);
      await tester.tap(confirmer);
      await tester.pumpAndSettle();

      expect(service.demandes, [(1500, MoyenRetrait.wave, '701234567')]);
      expect(find.text('Demande de retrait envoyée'), findsOneWidget);
      expect(find.textContaining('compte Wave (70 123 45 67)'), findsOneWidget);
    });

    testWidgets('montant ou numéro invalides : message sous le champ, confirmation bloquée, rien n\'est envoyé',
        (tester) async {
      final service = await ouvrir(tester);
      await ouvrirFeuille(tester);
      await tester.enterText(find.byKey(const ValueKey('montant-retrait')), '400');
      await tester.pump();
      expect(find.text('Retrait minimal : ${formaterFcfa(500)}.'), findsOneWidget);
      expect(actif(tester), isFalse);
      await tester.enterText(find.byKey(const ValueKey('montant-retrait')), '6000');
      await tester.pump();
      expect(find.text('Votre solde est de ${formaterFcfa(5000)}.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('montant-retrait')), '');
      await tester.pump();
      expect(find.text('Saisissez un montant.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('montant-retrait')), '1000');
      await tester.enterText(find.byKey(const ValueKey('numero-retrait')), '33 823 45 67');
      await tester.pump();
      expect(find.byKey(const ValueKey('erreur-numero-retrait')), findsOneWidget);
      expect(find.byKey(const ValueKey('resume-retrait')), findsNothing);
      expect(actif(tester), isFalse);
      await tester.tap(confirmer);
      await tester.pump();
      expect(service.demandes, isEmpty);
    });

    testWidgets('refus du serveur : son message dans la feuille, qui reste ouverte', (tester) async {
      final service = await ouvrir(
        tester,
        retraits: _RetraitsFactices(refus: ApiException('Un retrait est déjà en cours de traitement : attendez son versement.')),
      );
      await ouvrirFeuille(tester);
      await tester.tap(confirmer);
      await tester.pumpAndSettle();
      expect(service.demandes, isEmpty);
      expect(find.byKey(const ValueKey('erreur-serveur-retrait')), findsOneWidget);
      expect(find.text('Un retrait est déjà en cours de traitement : attendez son versement.'), findsOneWidget);
      expect(find.text('Retirer mon solde'), findsOneWidget);
      expect(find.text('Demande de retrait envoyée'), findsNothing);
    });

    testWidgets('retrait en attente : bandeau sous le solde ; « Retirer » l\'explique au lieu d\'ouvrir la feuille',
        (tester) async {
      final service = await ouvrir(tester);
      expect(service.suivis, 1);
      // Événement livré à la fin du premier pump, affiché au suivant.
      service.enCours.add(_enAttente);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bandeau-retrait')), findsOneWidget);
      expect(find.textContaining('Retrait en cours : ${formaterFcfa(1500)} vers Orange Money (77 123 45 67)'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bouton-retirer')));
      await tester.pumpAndSettle();
      expect(find.text('Retrait déjà en cours'), findsOneWidget);
      expect(find.text('Retirer mon solde'), findsNothing);
      await tester.tap(find.text('Compris'));
      await tester.pumpAndSettle();
      // Traité par l'Admin : le bandeau disparaît.
      service.enCours.add(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bandeau-retrait')), findsNothing);
    });

    testWidgets('solde sous le minimum : expliqué, pas de feuille', (tester) async {
      await ouvrir(tester, solde: 300);
      await ouvrirFeuille(tester);
      expect(find.text('Solde insuffisant'), findsOneWidget);
      expect(find.text('Retirer mon solde'), findsNothing);
    });
  });

  group('Admin : retraits à verser', () {
    Future<void> afficher(WidgetTester tester, _RetraitsFactices retraits) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminFinancesSection(
              service: _FinancesVides(),
              noms: Stream.value(const {}),
              maintenant: DateTime(2026, 11, 2, 14),
              retraits: retraits,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    final autreNumero = Retrait(
      id: 'rtr_000000000000000000000002',
      clientId: 'fatou',
      montantFcfa: 3000,
      moyen: MoyenRetrait.wave,
      numero: '781234567',
      nomClient: 'Fatou Sall',
      creeLe: DateTime(2026, 11, 2, 13),
    );

    testWidgets('aucun retrait (retraits fermés) : rien ne change sur la page', (tester) async {
      await afficher(tester, _RetraitsFactices());
      expect(find.byKey(const ValueKey('retraits-a-traiter')), findsNothing);
      expect(find.text('À verser aux chauffeurs'), findsOneWidget);
    });

    testWidgets('lecture des retraits impossible : le reste de la page Finances s\'affiche quand même', (tester) async {
      await afficher(tester, _RetraitsIllisibles());
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('retraits-a-traiter')), findsNothing);
      expect(find.text('À verser aux chauffeurs'), findsOneWidget);
    });

    testWidgets('retraits en attente : client, montant, moyen et numéro ; alerte si autre numéro que celui du compte',
        (tester) async {
      await afficher(tester, _RetraitsFactices(aTraiter: [_enAttente, autreNumero]));
      expect(find.byKey(const ValueKey('retraits-a-traiter')), findsOneWidget);
      expect(find.text('Retraits de solde à verser : 2 (${formaterFcfa(4500)})'), findsOneWidget);
      expect(find.text('Awa Ndiaye'), findsOneWidget);
      expect(find.text('Fatou Sall'), findsOneWidget);
      expect(find.textContaining('Orange Money · 77 123 45 67'), findsOneWidget);
      expect(find.textContaining('Wave · 78 123 45 67'), findsOneWidget);
      expect(find.textContaining('Numéro différent de celui du compte'), findsOneWidget);
      expect(find.text('À verser aux chauffeurs'), findsOneWidget);
    });

    testWidgets('« Marquer versé » : référence du transfert envoyée au serveur, client prévenu', (tester) async {
      final service = _RetraitsFactices(aTraiter: [_enAttente]);
      await afficher(tester, service);
      await tester.tap(find.text('Marquer versé'));
      await tester.pumpAndSettle();
      expect(find.text('Retrait versé à Awa Ndiaye'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('texte-traitement-retrait')), ' MP261102.1200.A00001 ');
      await tester.tap(find.text('Confirmer le versement'));
      await tester.pumpAndSettle();
      expect(service.traitements, [
        (id: _enAttente.id, verse: true, reference: 'MP261102.1200.A00001', motif: ''),
      ]);
      expect(find.text('Retrait marqué versé : Awa Ndiaye est prévenu.'), findsOneWidget);
    });

    testWidgets('« Refuser » : motif obligatoire, puis envoyé ; montant rendu au client', (tester) async {
      final service = _RetraitsFactices(aTraiter: [_enAttente]);
      await afficher(tester, service);
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      expect(find.text('Refuser le retrait de Awa Ndiaye'), findsOneWidget);
      await tester.tap(find.text('Refuser et rendre le montant'));
      await tester.pump();
      expect(find.text('Indiquez le motif du refus : il est envoyé au client.'), findsOneWidget);
      expect(service.traitements, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('texte-traitement-retrait')), 'Numéro injoignable');
      await tester.tap(find.text('Refuser et rendre le montant'));
      await tester.pumpAndSettle();
      expect(service.traitements, [(id: _enAttente.id, verse: false, reference: '', motif: 'Numéro injoignable')]);
      expect(find.text('Retrait refusé : ${formaterFcfa(1500)} rendus sur le solde de Awa Ndiaye.'), findsOneWidget);
    });

    testWidgets('refus du serveur (déjà traité) : son message dans la fenêtre, qui reste ouverte', (tester) async {
      final service = _RetraitsFactices(aTraiter: [_enAttente], refus: ApiException('Ce retrait a déjà été traité.'));
      await afficher(tester, service);
      await tester.tap(find.text('Marquer versé'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer le versement'));
      await tester.pumpAndSettle();
      expect(find.text('Ce retrait a déjà été traité.'), findsOneWidget);
      expect(find.text('Retrait versé à Awa Ndiaye'), findsOneWidget);
    });
  });
}
