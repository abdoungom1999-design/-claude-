import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/network/api_exception.dart';
import 'package:sprint/core/utils/format_fcfa.dart';
import 'package:sprint/core/widgets/primary_button.dart';
import 'package:sprint/core/widgets/wallet_card.dart';
import 'package:sprint/features/admin/presentation/sections/admin_finances_section.dart';
import 'package:sprint/features/compte/presentation/compte_tab_page.dart';
import 'package:sprint/features/compte/presentation/conditions_utilisation_page.dart';
import 'package:sprint/features/finances/data/comptabilite.dart';
import 'package:sprint/features/finances/data/finance_service.dart';
import 'package:sprint/features/portefeuille/data/portefeuille_service.dart';
import 'package:sprint/features/portefeuille/data/retraits.dart';

/// Retraits du solde (lot B), ouverts avec le go du client du 2 novembre
/// 2026 : frais de transfert déduits (payés par le client), envoi sous 48 h,
/// 50 000 FCFA par jour et par client ; seul l'argent réellement payé se
/// retire (règles appliquées par le serveur, reprises à l'affichage).

class _PortefeuilleFactice extends PortefeuilleService {
  _PortefeuilleFactice(this.portefeuille);

  final Portefeuille portefeuille;

  @override
  Stream<Portefeuille> streamPortefeuille(String uid) => Stream.value(portefeuille);

  @override
  Future<void> definirPayerAvecSolde(String uid, bool valeur) async {}
}

const _toutRetirable = InfosRetrait(
  soldeFcfa: 5000,
  retirableFcfa: 5000,
  resteDuJourFcfa: 50000,
  enCours: false,
  maximumFcfa: 5000,
);

class _RetraitsFactices extends RetraitService {
  _RetraitsFactices({this.refus, this.aTraiter = const [], List<Object> infos = const [_toutRetirable]})
      : _infos = [...infos];

  final Exception? refus;
  final List<Retrait> aTraiter;

  /// Réponses successives de `infosRetrait` (une [InfosRetrait] ou une exception).
  final List<Object> _infos;
  final enCours = StreamController<Retrait?>.broadcast();
  final demandes = <(int, MoyenRetrait, String)>[];
  final traitements = <({String id, bool verse, int frais, String reference, String motif})>[];
  var suivis = 0;
  var lectures = 0;

  @override
  Future<InfosRetrait> infos() async {
    lectures++;
    final reponse = _infos.length > 1 ? _infos.removeAt(0) : _infos.first;
    if (reponse is Exception) throw reponse;
    return reponse as InfosRetrait;
  }

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
  Future<void> traiter({
    required String retraitId,
    required bool verse,
    int fraisFcfa = 0,
    String reference = '',
    String motif = '',
  }) async {
    if (refus case final erreur?) throw erreur;
    traitements.add((id: retraitId, verse: verse, frais: fraisFcfa, reference: reference, motif: motif));
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
  aVerserAvant: DateTime(2026, 11, 4, 12, 5),
);

void main() {
  group('retraits : réglages et numéro', () {
    test('ouverts (go du client) : 500 FCFA au moins, 50 000 FCFA par jour, envoi sous 48 h, Orange Money ou Wave', () {
      expect(retraitsOuverts, isTrue);
      expect(retraitMinFcfa, 500);
      expect(retraitMaxJourFcfa, 50000);
      expect(delaiVersementHeures, 48);
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

    test('demande et infos lues du serveur ; libellés des mouvements', () {
      final r = Retrait.depuisDocument('rtr_1', {
        'clientId': 'awa',
        'montantFcfa': 1500,
        'moyen': 'WAVE',
        'numero': '701234567',
        'nomClient': 'Awa',
        'numeroDuCompte': true,
      });
      expect([r.clientId, r.montantFcfa, r.moyen, r.numeroLisible, r.nomClient, r.numeroDuCompte, r.aVerserAvant],
          ['awa', 1500, MoyenRetrait.wave, '70 123 45 67', 'Awa', true, null]);
      final vide = Retrait.depuisDocument('rtr_2', {});
      expect([vide.montantFcfa, vide.moyen, vide.nomClient, vide.numeroDuCompte], [0, null, 'Client', false]);
      final infos = InfosRetrait.depuis({
        'soldeFcfa': 23000,
        'retirableFcfa': 7000,
        'resteDuJourFcfa': 50000,
        'enCours': false,
        'maximumFcfa': 7000,
        'ouverts': true,
      });
      expect([infos.soldeFcfa, infos.retirableFcfa, infos.resteDuJourFcfa, infos.enCours, infos.maximumFcfa],
          [23000, 7000, 50000, false, 7000]);

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

    testWidgets('conditions d\'utilisation : règles des retraits, avec les valeurs en service', (tester) async {
      // Écran haut : toutes les sections construites (liste paresseuse).
      tester.view.physicalSize = const Size(900, 8000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ConditionsUtilisationPage()));
      await tester.pumpAndSettle();
      expect(find.text('Portefeuille Sprint et retraits'), findsOneWidget);
      final texte = find.textContaining('Le solde du Portefeuille Sprint sert à payer des courses');
      expect(texte, findsOneWidget);
      final clause = tester.widget<Text>(texte).data!;
      for (final attendu in [
        formaterFcfa(retraitMinFcfa),
        formaterFcfa(retraitMaxJourFcfa),
        '$delaiVersementHeures heures',
        'frais de transfert',
      ]) {
        expect(clause, contains(attendu));
      }
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

    testWidgets('sans retrait : seulement « Recharger », comme avant', (tester) async {
      await afficher(tester);
      expect(find.widgetWithText(ElevatedButton, 'Recharger'), findsOneWidget);
      expect(find.byKey(const ValueKey('bouton-retirer')), findsNothing);
      expect(find.text('Retirer'), findsNothing);
    });

    testWidgets('avec retrait : « Retirer » à côté de « Recharger »', (tester) async {
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
      _RetraitsFactices? retraits,
    }) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final service = retraits ?? _RetraitsFactices();
      await tester.pumpWidget(
        MaterialApp(
          home: CompteTabPage(
            service: _PortefeuilleFactice(const Portefeuille(soldeFcfa: 5000)),
            // Nouvel état à chaque ouverture (plusieurs cas dans un même test).
            key: UniqueKey(),
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

    testWidgets('retraits fermés : ni bouton, ni bandeau, ni lecture ; recharge « non retirable »', (tester) async {
      final service = await ouvrir(tester, ouverts: false);
      expect(find.byKey(const ValueKey('bouton-retirer')), findsNothing);
      expect(find.byKey(const ValueKey('bandeau-retrait')), findsNothing);
      expect([service.suivis, service.lectures], [0, 0]);
      await tester.tap(find.text('Recharger'));
      await tester.pumpAndSettle();
      expect(find.text('Le solde sert uniquement à payer vos courses. Il n\'est pas retirable.'), findsOneWidget);
    });

    testWidgets('retraits ouverts : la recharge dit que le solde peut être retiré, hors argent de test', (tester) async {
      await ouvrir(tester);
      await tester.tap(find.text('Recharger'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Il peut aussi être retiré (bouton « Retirer »), hors argent de test.'), findsOneWidget);
    });

    testWidgets('feuille : ce que le serveur permet est proposé, numéro du compte, 48 h et frais annoncés', (tester) async {
      final service = await ouvrir(tester);
      await ouvrirFeuille(tester);
      expect(service.lectures, 1);
      expect(find.text('Retirer mon solde'), findsOneWidget);
      expect(find.text('Vous pouvez retirer jusqu\'à ${formaterFcfa(5000)} maintenant.'), findsOneWidget);
      expect(find.textContaining('sous 48 h, frais de transfert de l\'opérateur déduits'), findsOneWidget);
      expect(find.textContaining('Plafond : ${formaterFcfa(50000)} par jour.'), findsOneWidget);
      expect(find.widgetWithText(TextField, '5000'), findsOneWidget);
      expect(find.widgetWithText(TextField, '77 123 45 67'), findsOneWidget);
      expect(
        find.text('Vous recevrez ${formaterFcfa(5000)} sur le 77 123 45 67 (Orange Money), moins les frais de transfert.'),
        findsOneWidget,
      );
      expect(actif(tester), isTrue);
    });

    testWidgets('argent de test et plafond du jour : le maximum proposé est celui du serveur, expliqué', (tester) async {
      await ouvrir(
        tester,
        retraits: _RetraitsFactices(infos: const [
          InfosRetrait(soldeFcfa: 23000, retirableFcfa: 7000, resteDuJourFcfa: 6000, enCours: false, maximumFcfa: 6000),
        ]),
      );
      await ouvrirFeuille(tester);
      final retirable = tester.widget<Text>(find.byKey(const ValueKey('retirable'))).data!;
      expect(retirable, startsWith('Vous pouvez retirer jusqu\'à ${formaterFcfa(6000)} maintenant'));
      expect(retirable, contains('l\'argent de test, qui sert à payer vos courses'));
      expect(retirable, contains('plafond du jour : encore ${formaterFcfa(6000)}'));
      expect(find.widgetWithText(TextField, '6000'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('montant-retrait')), '7000');
      await tester.pump();
      expect(find.text('Vous pouvez retirer au plus ${formaterFcfa(6000)} maintenant.'), findsOneWidget);
      expect(actif(tester), isFalse);
    });

    testWidgets('demande : montant, Wave et numéro envoyés au serveur ; confirmation (48 h, frais déduits)',
        (tester) async {
      final service = await ouvrir(tester);
      await ouvrirFeuille(tester);
      await tester.enterText(find.byKey(const ValueKey('montant-retrait')), '1500');
      await tester.tap(find.byKey(const ValueKey('moyen-retrait-WAVE')));
      await tester.enterText(find.byKey(const ValueKey('numero-retrait')), '+221 70 123 45 67');
      await tester.pump();
      expect(find.text('Numéro Wave'), findsOneWidget);
      expect(
        find.text('Vous recevrez ${formaterFcfa(1500)} sur le 70 123 45 67 (Wave), moins les frais de transfert.'),
        findsOneWidget,
      );
      await tester.tap(confirmer);
      await tester.pumpAndSettle();

      expect(service.demandes, [(1500, MoyenRetrait.wave, '701234567')]);
      expect(find.text('Demande de retrait envoyée'), findsOneWidget);
      expect(find.textContaining('sous 48 h sur votre compte Wave (70 123 45 67)'), findsOneWidget);
      expect(find.textContaining('frais de transfert de l\'opérateur déduits'), findsOneWidget);
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
      expect(find.text('Vous pouvez retirer au plus ${formaterFcfa(5000)} maintenant.'), findsOneWidget);
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

    testWidgets('rien à retirer : la raison est expliquée, pas de formulaire', (tester) async {
      const cas = {
        'Rien à retirer pour l\'instant':
            InfosRetrait(soldeFcfa: 20000, retirableFcfa: 0, resteDuJourFcfa: 50000, enCours: false, maximumFcfa: 0),
        'Plafond du jour atteint':
            InfosRetrait(soldeFcfa: 20000, retirableFcfa: 20000, resteDuJourFcfa: 0, enCours: false, maximumFcfa: 0),
        'Solde insuffisant':
            InfosRetrait(soldeFcfa: 300, retirableFcfa: 300, resteDuJourFcfa: 50000, enCours: false, maximumFcfa: 300),
        'Retrait déjà en cours':
            InfosRetrait(soldeFcfa: 3000, retirableFcfa: 3000, resteDuJourFcfa: 48500, enCours: true, maximumFcfa: 0),
      };
      for (final MapEntry(key: titre, value: infos) in cas.entries) {
        await ouvrir(tester, retraits: _RetraitsFactices(infos: [infos]));
        await ouvrirFeuille(tester);
        expect(find.byKey(const ValueKey('retrait-indisponible')), findsOneWidget, reason: titre);
        expect(find.text(titre), findsOneWidget, reason: titre);
        expect(find.byKey(const ValueKey('montant-retrait')), findsNothing, reason: titre);
        await tester.tap(find.text('Compris'));
        await tester.pumpAndSettle();
        expect(find.text('Retirer mon solde'), findsNothing, reason: titre);
      }
      expect(find.textContaining('mode test'), findsNothing, reason: 'feuille refermée');
    });

    testWidgets('vérification impossible : message et « Réessayer »', (tester) async {
      final service = await ouvrir(
        tester,
        retraits: _RetraitsFactices(infos: [ApiException('Impossible de contacter le serveur.'), _toutRetirable]),
      );
      await ouvrirFeuille(tester);
      expect(find.text('Impossible de contacter le serveur.'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(service.lectures, 2);
      expect(find.byKey(const ValueKey('montant-retrait')), findsOneWidget);
    });

    testWidgets('refus du serveur : son message dans la feuille, qui reste ouverte', (tester) async {
      final service = await ouvrir(
        tester,
        retraits: _RetraitsFactices(
          refus: ApiException('Plafond de 50 000 FCFA de retraits par jour : vous pouvez encore retirer 2 000 FCFA aujourd\'hui.'),
        ),
      );
      await ouvrirFeuille(tester);
      await tester.tap(confirmer);
      await tester.pumpAndSettle();
      expect(service.demandes, isEmpty);
      expect(find.byKey(const ValueKey('erreur-serveur-retrait')), findsOneWidget);
      expect(find.textContaining('vous pouvez encore retirer 2 000 FCFA aujourd\'hui'), findsOneWidget);
      expect(find.text('Retirer mon solde'), findsOneWidget);
      expect(find.text('Demande de retrait envoyée'), findsNothing);
    });

    testWidgets('retrait en attente : bandeau (48 h, frais) ; « Retirer » l\'explique sans interroger le serveur',
        (tester) async {
      final service = await ouvrir(tester);
      expect(service.suivis, 1);
      // Événement livré à la fin du premier pump, affiché au suivant.
      service.enCours.add(_enAttente);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bandeau-retrait')), findsOneWidget);
      expect(
        find.text('Retrait en cours : ${formaterFcfa(1500)} vers Orange Money (77 123 45 67), envoyés sous 48 h, '
            'frais de transfert déduits.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('bouton-retirer')));
      await tester.pumpAndSettle();
      expect(find.text('Retrait déjà en cours'), findsOneWidget);
      expect(find.text('Retirer mon solde'), findsNothing);
      expect(service.lectures, 0);
      await tester.tap(find.text('Compris'));
      await tester.pumpAndSettle();
      // Traité par l'Admin : le bandeau disparaît.
      service.enCours.add(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bandeau-retrait')), findsNothing);
    });
  });

  group('Admin : retraits à verser', () {
    Future<void> afficher(WidgetTester tester, _RetraitsFactices retraits, {DateTime? maintenant}) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminFinancesSection(
              service: _FinancesVides(),
              noms: Stream.value(const {}),
              maintenant: maintenant ?? DateTime(2026, 11, 2, 14),
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
      aVerserAvant: DateTime(2026, 11, 4, 13),
    );

    testWidgets('aucun retrait : « Aucun retrait à verser », le reste de la page est inchangé', (tester) async {
      await afficher(tester, _RetraitsFactices());
      expect(find.byKey(const ValueKey('retraits-a-traiter')), findsOneWidget);
      expect(find.text('Aucun retrait à verser.'), findsOneWidget);
      expect(find.text('À verser aux chauffeurs'), findsOneWidget);
    });

    testWidgets('lecture des retraits impossible : le reste de la page Finances s\'affiche quand même', (tester) async {
      await afficher(tester, _RetraitsIllisibles());
      expect(tester.takeException(), isNull);
      expect(find.text('À verser aux chauffeurs'), findsOneWidget);
    });

    testWidgets('retraits en attente : client, montant, moyen, numéro, échéance de 48 h ; alerte si autre numéro',
        (tester) async {
      await afficher(tester, _RetraitsFactices(aTraiter: [_enAttente, autreNumero]));
      expect(find.byKey(const ValueKey('retraits-a-traiter')), findsOneWidget);
      expect(find.text('Retraits de solde à verser : 2 (${formaterFcfa(4500)})'), findsOneWidget);
      expect(find.textContaining('sous 48 h'), findsOneWidget);
      expect(find.text('Awa Ndiaye'), findsOneWidget);
      expect(find.text('Fatou Sall'), findsOneWidget);
      expect(find.textContaining('Orange Money · 77 123 45 67'), findsOneWidget);
      expect(find.textContaining('Wave · 78 123 45 67'), findsOneWidget);
      expect(find.text('À envoyer avant le 04/11 à 12h05'), findsOneWidget);
      expect(find.byKey(const ValueKey('retrait-en-retard')), findsNothing);
      expect(find.textContaining('Numéro différent de celui du compte'), findsOneWidget);
    });

    testWidgets('échéance dépassée : « En retard » en évidence', (tester) async {
      await afficher(tester, _RetraitsFactices(aTraiter: [_enAttente]), maintenant: DateTime(2026, 11, 4, 13));
      expect(find.byKey(const ValueKey('retrait-en-retard')), findsOneWidget);
      expect(find.text('En retard : promis au client avant le 04/11 à 12h05'), findsOneWidget);
    });

    testWidgets('« Marquer versé » : frais déduits (montant à envoyer calculé) et référence envoyés au serveur',
        (tester) async {
      final service = _RetraitsFactices(aTraiter: [_enAttente]);
      await afficher(tester, service);
      await tester.tap(find.text('Marquer versé'));
      await tester.pumpAndSettle();
      expect(find.text('Retrait versé à Awa Ndiaye'), findsOneWidget);
      // Sans frais saisis : refusé (0 s'il n'y en a pas).
      await tester.tap(find.text('Confirmer le versement'));
      await tester.pump();
      expect(find.text('Indiquez les frais de transfert (0 s\'il n\'y en a pas).'), findsOneWidget);
      // Trop élevés (10 % au plus, 100 FCFA au moins) : refusé.
      await tester.enterText(find.byKey(const ValueKey('frais-retrait')), '200');
      await tester.tap(find.text('Confirmer le versement'));
      await tester.pump();
      expect(find.text('Frais trop élevés : ${formaterFcfa(150)} au plus. Vérifiez la saisie.'), findsOneWidget);
      expect(service.traitements, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('frais-retrait')), '15');
      await tester.pump();
      expect(find.text('Montant à envoyer : ${formaterFcfa(1485)}'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('texte-traitement-retrait')), ' MP261102.1200.A00001 ');
      await tester.tap(find.text('Confirmer le versement'));
      await tester.pumpAndSettle();
      expect(service.traitements, [
        (id: _enAttente.id, verse: true, frais: 15, reference: 'MP261102.1200.A00001', motif: ''),
      ]);
      expect(find.text('Retrait marqué versé : Awa Ndiaye est prévenu.'), findsOneWidget);
    });

    testWidgets('« Refuser » : motif obligatoire, puis envoyé ; montant rendu au client', (tester) async {
      final service = _RetraitsFactices(aTraiter: [_enAttente]);
      await afficher(tester, service);
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      expect(find.text('Refuser le retrait de Awa Ndiaye'), findsOneWidget);
      expect(find.byKey(const ValueKey('frais-retrait')), findsNothing);
      await tester.tap(find.text('Refuser et rendre le montant'));
      await tester.pump();
      expect(find.text('Indiquez le motif du refus : il est envoyé au client.'), findsOneWidget);
      expect(service.traitements, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('texte-traitement-retrait')), 'Numéro injoignable');
      await tester.tap(find.text('Refuser et rendre le montant'));
      await tester.pumpAndSettle();
      expect(service.traitements, [(id: _enAttente.id, verse: false, frais: 0, reference: '', motif: 'Numéro injoignable')]);
      expect(find.text('Retrait refusé : ${formaterFcfa(1500)} rendus sur le solde de Awa Ndiaye.'), findsOneWidget);
    });

    testWidgets('refus du serveur (déjà traité) : son message dans la fenêtre, qui reste ouverte', (tester) async {
      final service = _RetraitsFactices(aTraiter: [_enAttente], refus: ApiException('Ce retrait a déjà été traité.'));
      await afficher(tester, service);
      await tester.tap(find.text('Marquer versé'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('frais-retrait')), '0');
      await tester.tap(find.text('Confirmer le versement'));
      await tester.pumpAndSettle();
      expect(find.text('Ce retrait a déjà été traité.'), findsOneWidget);
      expect(find.text('Retrait versé à Awa Ndiaye'), findsOneWidget);
    });
  });
}
