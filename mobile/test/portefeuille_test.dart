import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/demo/demo_data.dart';
import 'package:sprint/core/network/api_exception.dart';
import 'package:sprint/core/utils/format_fcfa.dart';
import 'package:sprint/core/widgets/payment_method_selector.dart';
import 'package:sprint/core/widgets/payment_method_sheet.dart';
import 'package:sprint/features/admin/presentation/admin_portefeuille_page.dart';
import 'package:sprint/features/client/presentation/payment_processing_page.dart';
import 'package:sprint/features/compte/presentation/compte_tab_page.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/portefeuille/data/portefeuille_service.dart';
import 'package:sprint/features/portefeuille/presentation/mouvements_portefeuille_page.dart';
import 'package:sprint/features/portefeuille/presentation/recharge_portefeuille_page.dart';

/// Faux service : aucun accès Firebase, tout est piloté par le test.
class _ServiceFactice extends PortefeuilleService {
  _ServiceFactice({
    this.refusRecharge,
    Portefeuille portefeuille = const Portefeuille(),
    List<MouvementPortefeuille> mouvements = const [],
    this.refusAjustement,
  })  : _portefeuille = portefeuille,
        _mouvements = mouvements;

  final Exception? refusRecharge;
  final Exception? refusAjustement;
  final Portefeuille _portefeuille;
  final List<MouvementPortefeuille> _mouvements;

  final avancement = StreamController<AvancementRecharge?>();
  final preferences = <(String, bool)>[];
  int? montantRecu;
  String? methodeRecue;
  final ajustements = <({String clientId, int montant, String motif})>[];

  @override
  Future<RechargeDemandee> creerRecharge({required int montantFcfa, required String methodePaiement}) async {
    montantRecu = montantFcfa;
    methodeRecue = methodePaiement;
    if (refusRecharge case final erreur?) throw erreur;
    return RechargeDemandee(
      rechargeId: 'rch_1',
      lienPaiement: Uri.parse('https://paiement.test/?session=sim_r1'),
      montantFcfa: montantFcfa,
    );
  }

  @override
  Stream<AvancementRecharge?> streamRecharge(String rechargeId) => avancement.stream;

  @override
  Stream<Portefeuille> streamPortefeuille(String uid) => Stream.value(_portefeuille);

  @override
  Future<void> definirPayerAvecSolde(String uid, bool valeur) async => preferences.add((uid, valeur));

  @override
  Stream<List<MouvementPortefeuille>> streamMouvements(String uid) => Stream.value(_mouvements);

  @override
  Future<int> ajuster({required String clientId, required int montantFcfa, required String motif}) async {
    if (refusAjustement case final erreur?) throw erreur;
    ajustements.add((clientId: clientId, montant: montantFcfa, motif: motif));
    return _portefeuille.soldeFcfa + montantFcfa;
  }
}

MouvementPortefeuille _mouvement(String id, String type, int montant, int solde, {String? note}) =>
    MouvementPortefeuille(
      id: id,
      type: type,
      montantFcfa: montant,
      soldeApresFcfa: solde,
      note: note,
      creeLe: DateTime(2026, 9, 27, 14, 5),
    );

void main() {
  group('modèles', () {
    test('portefeuille : document absent, incomplet ou mal typé = solde nul', () {
      expect(Portefeuille.depuisDocument(null).soldeFcfa, 0);
      expect(Portefeuille.depuisDocument({'payerAvecSolde': true}).soldeFcfa, 0);
      expect(Portefeuille.depuisDocument({'payerAvecSolde': true}).payerAvecSolde, isTrue);
      expect(Portefeuille.depuisDocument({'soldeFcfa': 'x', 'payerAvecSolde': 'oui'}).soldeFcfa, 0);
      expect(Portefeuille.depuisDocument({'soldeFcfa': 'x', 'payerAvecSolde': 'oui'}).payerAvecSolde, isFalse);
      expect(Portefeuille.depuisDocument({'soldeFcfa': 5000}).soldeFcfa, 5000);
    });

    test('le solde couvre une course s\'il est au moins égal au prix', () {
      const p = Portefeuille(soldeFcfa: 2300);
      expect(p.couvre(2300), isTrue);
      expect(p.couvre(2301), isFalse);
    });

    test('recharge encore possible avant le plafond de 200 000 FCFA', () {
      expect(const Portefeuille().rechargePossibleFcfa, 200000);
      expect(const Portefeuille(soldeFcfa: 150000).rechargePossibleFcfa, 50000);
      expect(const Portefeuille(soldeFcfa: 200000).rechargePossibleFcfa, 0);
      expect(const Portefeuille(soldeFcfa: 230000).rechargePossibleFcfa, 0);
    });

    test('limites : mêmes valeurs que le serveur', () {
      expect(LimitesPortefeuille.rechargeMinFcfa, 500);
      expect(LimitesPortefeuille.rechargeMaxFcfa, 100000);
      expect(LimitesPortefeuille.soldeMaxFcfa, 200000);
    });

    test('mouvements : libellés et lecture d\'un document', () {
      expect(MouvementPortefeuille.depuisDocument('a', {'type': 'recharge', 'montantFcfa': 500}).libelle, 'Recharge');
      expect(_mouvement('b', MouvementPortefeuille.paiementCourse, -2300, 0).libelle, 'Paiement d\'une course');
      expect(_mouvement('c', MouvementPortefeuille.remboursement, 2300, 0).libelle, 'Remboursement d\'une course');
      expect(_mouvement('d', MouvementPortefeuille.ajustementAdmin, 100, 0).libelle, 'Ajustement Sprint');
      final vide = MouvementPortefeuille.depuisDocument('e', {});
      expect(vide.montantFcfa, 0);
      expect(vide.libelle, 'Mouvement');
    });

    test('le solde Sprint est un mode de paiement distinct côté serveur', () {
      expect(PaymentMethod.portefeuille.apiValue, 'PORTEFEUILLE');
      expect(PaymentMethod.portefeuille.label, 'Solde Sprint');
    });

    test('course payée avec le solde : libellé dédié, jamais « payé par Wave »', () {
      final donnees = {
        'clientId': 'awa',
        'statut': 'en_attente',
        'type': 'PASSAGER',
        'prixFcfa': 2300,
        'methodePaiement': 'PORTEFEUILLE',
      };
      expect(CourseFirestore.depuisDocument('c1', donnees).libellePaiement, 'Déjà payé avec le solde Sprint');
    });
  });

  group('choix du mode de paiement d\'une commande', () {
    Future<Future<PaymentMethod?> Function()> ouvrir(
      WidgetTester tester, {
      Portefeuille? portefeuille,
      int montant = 2300,
    }) async {
      PaymentMethod? choix;
      var termine = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choix = await afficherSelectionPaiementSheet(context, montantFcfa: montant, portefeuille: portefeuille);
              termine = true;
            },
            child: const Text('Ouvrir'),
          ),
        ),
      ));
      return () async {
        expect(termine, isTrue);
        return choix;
      };
    }

    Future<void> ouvrirSheet(WidgetTester tester) async {
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
    }

    final boutonSolde = find.byKey(const ValueKey('payer-avec-solde'));
    final avertissement = find.byKey(const ValueKey('solde-insuffisant'));

    testWidgets('sans portefeuille (démo, hors connexion) : Wave seulement', (tester) async {
      await ouvrir(tester);
      await ouvrirSheet(tester);
      expect(boutonSolde, findsNothing);
      expect(avertissement, findsNothing);
      expect(find.text('Payer avec Wave'), findsOneWidget);
      expect(find.text('Payer avec Orange Money'), findsNothing);
    });

    testWidgets('interrupteur éteint : le solde n\'est pas proposé, même suffisant', (tester) async {
      await ouvrir(tester, portefeuille: const Portefeuille(soldeFcfa: 50000));
      await ouvrirSheet(tester);
      expect(boutonSolde, findsNothing);
      expect(avertissement, findsNothing);
    });

    testWidgets('interrupteur actif et solde suffisant : « Payer avec mon solde » en premier', (tester) async {
      final resultat = await ouvrir(tester, portefeuille: const Portefeuille(soldeFcfa: 5000, payerAvecSolde: true));
      await ouvrirSheet(tester);
      expect(boutonSolde, findsOneWidget);
      expect(find.text('Payer avec mon solde'), findsOneWidget);
      expect(find.text('Solde ${formaterFcfa(5000)} · il restera ${formaterFcfa(2700)}'), findsOneWidget);
      expect(avertissement, findsNothing);
      // Wave reste disponible en dessous.
      expect(find.text('Payer avec Wave'), findsOneWidget);
      expect(tester.getTopLeft(boutonSolde).dy, lessThan(tester.getTopLeft(find.text('Payer avec Wave')).dy));

      await tester.tap(boutonSolde);
      await tester.pumpAndSettle();
      expect(await resultat(), PaymentMethod.portefeuille);
    });

    testWidgets('solde exactement égal au prix : accepté, il restera 0', (tester) async {
      await ouvrir(tester, portefeuille: const Portefeuille(soldeFcfa: 2300, payerAvecSolde: true));
      await ouvrirSheet(tester);
      expect(boutonSolde, findsOneWidget);
      expect(find.text('Solde ${formaterFcfa(2300)} · il restera ${formaterFcfa(0)}'), findsOneWidget);
    });

    testWidgets('solde insuffisant : le client est prévenu et paie le total par mobile money', (tester) async {
      final resultat = await ouvrir(tester, portefeuille: const Portefeuille(soldeFcfa: 2299, payerAvecSolde: true));
      await ouvrirSheet(tester);
      expect(boutonSolde, findsNothing);
      expect(avertissement, findsOneWidget);
      expect(find.textContaining(formaterFcfa(2299)), findsOneWidget);
      expect(find.text('Payer avec Wave'), findsOneWidget);

      expect(find.text('Payer avec Orange Money'), findsNothing);
      await tester.tap(find.text('Payer avec Wave'));
      await tester.pumpAndSettle();
      expect(await resultat(), PaymentMethod.wave);
    });
  });

  group('paiement d\'une course avec le solde (sas)', () {
    Future<Future<String?> Function()> ouvrirSas(WidgetTester tester, CourseService serveur) async {
      String? retour;
      var termine = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              retour = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => PaymentProcessingPage(
                    methode: PaymentMethod.portefeuille,
                    type: 'PASSAGER',
                    adresseDepart: 'Plateau',
                    adresseArrivee: 'Almadies',
                    prixFcfa: 2300,
                    points: const PointsCourse(
                      latitudeDepart: 14.668,
                      longitudeDepart: -17.438,
                      latitudeArrivee: 14.745,
                      longitudeArrivee: -17.517,
                    ),
                    courseService: serveur,
                    ouvrirLien: (_) async => fail('aucune page de paiement à ouvrir avec le solde'),
                  ),
                ),
              );
              termine = true;
            },
            child: const Text('Commander'),
          ),
        ),
      ));
      return () async {
        expect(termine, isTrue);
        return retour;
      };
    }

    testWidgets('débit fait par le serveur : pas de page opérateur, la course est suivie dès la confirmation',
        (tester) async {
      final serveur = _ServeurSolde();
      await ouvrirSas(tester, serveur);
      await tester.tap(find.text('Commander'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(serveur.methodeRecue, 'PORTEFEUILLE');
      expect(serveur.prixRecu, 2300);
      expect(find.text('Paiement avec votre solde Sprint…'), findsOneWidget);
      expect(find.textContaining('Payer avec'), findsNothing);
      expect(find.text('Annuler'), findsNothing);
      expect(serveur.commandeSuivie, 'k1');

      serveur.commande.add(const CommandePaiement(statut: StatutCommande.payee, courseId: 'course-1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Paiement confirmé !'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      // SuiviCoursePage écoute Firestore, indisponible dans les tests.
      tester.takeException();
    });

    testWidgets('solde insuffisant côté serveur : retour à la commande, rien de créé', (tester) async {
      final resultat = await ouvrirSas(
        tester,
        _ServeurSolde(
          refus: ApiException('Solde insuffisant : 2000 FCFA disponibles pour une course de 2300 FCFA.'),
        ),
      );
      await tester.tap(find.text('Commander'));
      await tester.pumpAndSettle();

      expect(
        await resultat(),
        "Solde insuffisant : 2000 FCFA disponibles pour une course de 2300 FCFA. Aucune course n'a été créée.",
      );
      expect(find.text('Commander'), findsOneWidget);
    });
  });

  group('recharge du portefeuille (sas)', () {
    Future<Future<Object?> Function()> ouvrir(
      WidgetTester tester,
      _ServiceFactice service, {
      int montant = 5000,
      PaymentMethod methode = PaymentMethod.wave,
      bool lienOuvrable = true,
      List<Uri>? liens,
    }) async {
      Object? retour;
      var termine = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              retour = await Navigator.of(context).push<Object>(
                MaterialPageRoute(
                  builder: (_) => RechargePortefeuillePage(
                    montantFcfa: montant,
                    methode: methode,
                    service: service,
                    ouvrirLien: (lien) async {
                      liens?.add(lien);
                      return lienOuvrable;
                    },
                  ),
                ),
              );
              termine = true;
            },
            child: const Text('Recharger'),
          ),
        ),
      ));
      return () async {
        expect(termine, isTrue);
        return retour;
      };
    }

    Future<void> demarrer(WidgetTester tester) async {
      await tester.tap(find.text('Recharger'));
      await tester.pumpAndSettle();
    }

    testWidgets('le serveur reçoit montant et opérateur ; le client paie sur la page de l\'opérateur', (tester) async {
      final service = _ServiceFactice();
      final liens = <Uri>[];
      await ouvrir(tester, service, methode: PaymentMethod.wave, liens: liens);
      await demarrer(tester);

      expect(service.montantRecu, 5000);
      expect(service.methodeRecue, 'WAVE');
      expect(find.text('Payer avec Wave · ${formaterFcfa(5000)}'), findsOneWidget);
      await tester.tap(find.text('Payer avec Wave · ${formaterFcfa(5000)}'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(liens, [Uri.parse('https://paiement.test/?session=sim_r1')]);
      expect(find.textContaining('En attente de la confirmation'), findsOneWidget);
    });

    testWidgets('l\'app ne crédite jamais d\'elle-même : rien tant que le serveur n\'a pas confirmé', (tester) async {
      final service = _ServiceFactice();
      await ouvrir(tester, service);
      await demarrer(tester);
      await tester.tap(find.textContaining('Payer avec Wave'));
      await tester.pump();

      service.avancement.add(const AvancementRecharge(statut: StatutRecharge.enAttente));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Portefeuille rechargé !'), findsNothing);
      expect(find.textContaining('En attente de la confirmation'), findsOneWidget);
    });

    testWidgets('recharge confirmée par le serveur : message de succès, retour « true »', (tester) async {
      final service = _ServiceFactice();
      final resultat = await ouvrir(tester, service);
      await demarrer(tester);
      await tester.tap(find.textContaining('Payer avec Wave'));
      await tester.pump();

      service.avancement.add(const AvancementRecharge(statut: StatutRecharge.reussie));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Portefeuille rechargé !'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(await resultat(), true);
    });

    testWidgets('paiement refusé chez l\'opérateur : message, solde inchangé', (tester) async {
      final service = _ServiceFactice();
      final resultat = await ouvrir(tester, service);
      await demarrer(tester);

      service.avancement.add(const AvancementRecharge(statut: StatutRecharge.echouee));
      await tester.pumpAndSettle();
      expect(await resultat(), "Recharge Wave refusée ou annulée. Votre solde n'a pas changé.");
    });

    testWidgets('délai dépassé : message', (tester) async {
      final service = _ServiceFactice();
      final resultat = await ouvrir(tester, service);
      await demarrer(tester);

      service.avancement.add(const AvancementRecharge(statut: StatutRecharge.expiree));
      await tester.pumpAndSettle();
      expect(await resultat(), "Le délai de paiement est dépassé. Votre solde n'a pas changé.");
    });

    testWidgets('anomalie de montant : le client est rassuré sur le remboursement', (tester) async {
      final service = _ServiceFactice();
      final resultat = await ouvrir(tester, service);
      await demarrer(tester);

      service.avancement.add(const AvancementRecharge(statut: 'anomalie'));
      await tester.pumpAndSettle();
      expect(await resultat(), contains('vous serez remboursé'));
    });

    testWidgets('plafond dépassé (refus du serveur) : son message est affiché, rien n\'est payé', (tester) async {
      final service = _ServiceFactice(
        refusRecharge: ApiException('Le solde du portefeuille est plafonné à 200000 FCFA. Vous pouvez encore recharger 1000 FCFA.'),
      );
      final resultat = await ouvrir(tester, service);
      await demarrer(tester);
      expect(await resultat(), contains('plafonné à 200000 FCFA'));
      expect(find.textContaining('Payer avec'), findsNothing);
    });

    testWidgets('erreur réseau : message neutre, solde inchangé', (tester) async {
      final service = _ServiceFactice(refusRecharge: Exception('réseau'));
      final resultat = await ouvrir(tester, service);
      await demarrer(tester);
      expect(await resultat(), "La recharge Wave n'a pas pu être préparée. Votre solde n'a pas changé.");
    });

    testWidgets('flèche « Retour » visible : elle annule la recharge', (tester) async {
      final service = _ServiceFactice();
      final resultat = await ouvrir(tester, service);
      await demarrer(tester);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(await resultat(), "Recharge annulée. Votre solde n'a pas changé.");
    });

    testWidgets('page de paiement impossible à ouvrir : message, le client reste dans le sas', (tester) async {
      final service = _ServiceFactice();
      final resultat = await ouvrir(tester, service, lienOuvrable: false);
      await demarrer(tester);
      await tester.tap(find.textContaining('Payer avec Wave'));
      await tester.pump();

      expect(find.text("Impossible d'ouvrir la page de paiement Wave. Réessayez."), findsOneWidget);
      expect(find.textContaining('Payer avec Wave'), findsOneWidget);
      expect(() => resultat(), throwsA(anything)); // toujours ouvert : pas de retour
    });
  });

  group('onglet Compte : recharge (mode démo)', () {
    setUp(() => DemoData.soldePortefeuilleFcfa = 0);
    tearDown(() => DemoData.soldePortefeuilleFcfa = 0);

    Future<void> ouvrirRecharge(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: CompteTabPage(demo: true, profil: Stream.value(null))));
      await tester.pump();
      await tester.tap(find.text('Recharger'));
      await tester.pumpAndSettle();
    }

    final erreur = find.byKey(const ValueKey('erreur-recharge'));
    final confirmer = find.text('Confirmer la recharge');

    Future<void> saisir(WidgetTester tester, String texte) async {
      await tester.enterText(find.byKey(const ValueKey('autre-montant')), texte);
      await tester.pump();
    }

    testWidgets('montants rapides, autre montant, opérateur Wave (Orange Money fermé)', (tester) async {
      await ouvrirRecharge(tester);
      expect(find.text('Recharger mon portefeuille'), findsWidgets);
      for (final montant in [1000, 2000, 5000, 10000, 20000]) {
        expect(find.text('$montant FCFA'), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('autre-montant')), findsOneWidget);
      expect(find.byKey(const ValueKey('operateur-WAVE')), findsOneWidget);
      expect(find.byKey(const ValueKey('operateur-ORANGE_MONEY')), findsNothing);
      expect(find.textContaining('Orange', findRichText: true), findsNothing);
      expect(find.textContaining('pas retirable'), findsOneWidget);
      expect(erreur, findsNothing);
    });

    testWidgets('minimum 500 FCFA : en dessous, message et confirmation bloquée', (tester) async {
      await ouvrirRecharge(tester);
      await saisir(tester, '499');
      expect(find.text('Recharge minimale : ${formaterFcfa(500)}.'), findsOneWidget);
      await tester.tap(confirmer, warnIfMissed: false);
      await tester.pump();
      expect(find.text('Recharger mon portefeuille'), findsWidgets); // la sheet reste ouverte
      expect(DemoData.soldePortefeuilleFcfa, 0);
      await saisir(tester, '500');
      expect(erreur, findsNothing);
    });

    testWidgets('maximum 100 000 FCFA par recharge', (tester) async {
      await ouvrirRecharge(tester);
      await saisir(tester, '100001');
      expect(find.text('Recharge maximale : ${formaterFcfa(100000)}.'), findsOneWidget);
      await saisir(tester, '100000');
      expect(erreur, findsNothing);
    });

    testWidgets('montant vide ou illisible : refusé', (tester) async {
      await ouvrirRecharge(tester);
      await saisir(tester, 'abc');
      expect(find.text('Saisissez un montant.'), findsOneWidget);
    });

    testWidgets('recharge démo : solde crédité immédiatement, message de confirmation', (tester) async {
      await ouvrirRecharge(tester);
      await saisir(tester, '5000');
      await tester.tap(confirmer);
      await tester.pumpAndSettle();
      expect(DemoData.soldePortefeuilleFcfa, 5000);
      expect(find.text('Votre solde a été crédité de 5000 FCFA.'), findsOneWidget);
    });

    testWidgets('l\'interrupteur « Régler mes courses avec mon solde » se règle en démo', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: CompteTabPage(demo: true, profil: Stream.value(null))));
      await tester.pump();
      final interrupteur = find.byType(Switch);
      expect(tester.widget<Switch>(interrupteur).value, isFalse);
      await tester.tap(interrupteur);
      await tester.pump();
      expect(tester.widget<Switch>(interrupteur).value, isTrue);
    });
  });

  group('onglet Compte : portefeuille réel (Firebase)', () {
    Future<_ServiceFactice> ouvrir(WidgetTester tester, {Portefeuille portefeuille = const Portefeuille()}) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final service = _ServiceFactice(portefeuille: portefeuille);
      await tester.pumpWidget(
        MaterialApp(home: CompteTabPage(service: service, clientId: 'awa', profil: Stream.value(null))),
      );
      await tester.pump();
      return service;
    }

    testWidgets('le solde affiché est celui du serveur, jamais le solde de démonstration', (tester) async {
      DemoData.soldePortefeuilleFcfa = 777;
      addTearDown(() => DemoData.soldePortefeuilleFcfa = 0);
      await ouvrir(tester, portefeuille: const Portefeuille(soldeFcfa: 12500));
      expect(find.text('12500 FCFA'), findsOneWidget);
      expect(find.text('777 FCFA'), findsNothing);
    });

    testWidgets('l\'interrupteur est enregistré côté serveur (portefeuilles/{uid}) et reflète l\'état lu', (tester) async {
      final service = await ouvrir(tester, portefeuille: const Portefeuille(soldeFcfa: 5000, payerAvecSolde: true));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(service.preferences, [('awa', false)]);
    });

    testWidgets('« Mouvements du portefeuille » est proposé', (tester) async {
      await ouvrir(tester);
      expect(find.text('Mouvements du portefeuille'), findsOneWidget);
    });

    testWidgets('recharge : le sas est ouvert avec le montant et l\'opérateur choisis, rien n\'est crédité d\'avance',
        (tester) async {
      final service = await ouvrir(tester);
      await tester.tap(find.text('Recharger'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5000 FCFA'));
      await tester.tap(find.byKey(const ValueKey('operateur-WAVE')));
      await tester.pump();
      await tester.tap(find.text('Confirmer la recharge'));
      await tester.pumpAndSettle();

      expect(service.montantRecu, 5000);
      expect(service.methodeRecue, 'WAVE');
      expect(find.text('Payer avec Wave · ${formaterFcfa(5000)}'), findsOneWidget);
      expect(DemoData.soldePortefeuilleFcfa, 0);
    });

    testWidgets('solde au plafond : la recharge est refusée dès la saisie', (tester) async {
      await ouvrir(tester, portefeuille: const Portefeuille(soldeFcfa: 200000));
      await tester.tap(find.text('Recharger'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('erreur-recharge')), findsOneWidget);
      expect(find.textContaining('plafond'), findsWidgets);
    });

    testWidgets('solde proche du plafond : indique ce qu\'il est encore possible d\'ajouter', (tester) async {
      await ouvrir(tester, portefeuille: const Portefeuille(soldeFcfa: 195000));
      await tester.tap(find.text('Recharger'));
      await tester.pumpAndSettle();
      // 2 000 FCFA (choix par défaut) reste possible ; 10 000 dépasse le plafond.
      expect(find.byKey(const ValueKey('erreur-recharge')), findsNothing);
      await tester.tap(find.text('10000 FCFA'));
      await tester.pump();
      expect(find.textContaining('encore ajouter ${formaterFcfa(5000)}'), findsOneWidget);
    });
  });

  group('historique du portefeuille', () {
    testWidgets('crédits en vert, débits, solde après chaque mouvement', (tester) async {
      final service = _ServiceFactice(mouvements: [
        _mouvement('3', MouvementPortefeuille.paiementCourse, -2300, 2700),
        _mouvement('2', MouvementPortefeuille.recharge, 5000, 5000),
        _mouvement('1', MouvementPortefeuille.ajustementAdmin, 300, 300, note: 'geste commercial'),
      ]);
      await tester.pumpWidget(MaterialApp(home: MouvementsPortefeuillePage(service: service, uid: 'awa')));
      await tester.pumpAndSettle();

      expect(find.text('Paiement d\'une course'), findsOneWidget);
      expect(find.text('− ${formaterFcfa(2300)}'), findsOneWidget);
      expect(find.text('+ ${formaterFcfa(5000)}'), findsOneWidget);
      expect(find.text('Solde ${formaterFcfa(2700)}'), findsOneWidget);
      expect(find.text('geste commercial'), findsOneWidget);
      expect(find.text('27/09/2026 14:05'), findsNWidgets(3));
    });

    testWidgets('aucun mouvement : message d\'accueil', (tester) async {
      await tester.pumpWidget(MaterialApp(home: MouvementsPortefeuillePage(service: _ServiceFactice(), uid: 'awa')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aucun mouvement'), findsOneWidget);
    });
  });

  group('Admin : portefeuille d\'un client', () {
    Future<_ServiceFactice> ouvrir(
      WidgetTester tester, {
      required int solde,
      required List<MouvementPortefeuille> mouvements,
      Exception? refus,
    }) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final service = _ServiceFactice(
        portefeuille: Portefeuille(soldeFcfa: solde),
        mouvements: mouvements,
        refusAjustement: refus,
      );
      await tester.pumpWidget(
        MaterialApp(home: AdminPortefeuillePage(clientId: 'awa', nomClient: 'Awa Diop', service: service)),
      );
      await tester.pumpAndSettle();
      return service;
    }

    Future<void> remplir(WidgetTester tester, {String montant = '', String motif = ''}) async {
      await tester.enterText(find.byKey(const ValueKey('ajustement-montant')), montant);
      await tester.enterText(find.byKey(const ValueKey('ajustement-motif')), motif);
      await tester.pump();
    }

    final enregistrer = find.text('Enregistrer l\'ajustement');

    testWidgets('solde et livre de comptes cohérent', (tester) async {
      await ouvrir(tester, solde: 2700, mouvements: [
        _mouvement('2', MouvementPortefeuille.paiementCourse, -2300, 2700),
        _mouvement('1', MouvementPortefeuille.recharge, 5000, 5000),
      ]);
      expect(find.byKey(const ValueKey('solde-admin')), findsOneWidget);
      expect(find.text(formaterFcfa(2700)), findsWidgets);
      expect(find.text('Livre de comptes cohérent'), findsOneWidget);
      expect(find.byKey(const ValueKey('incoherence')), findsNothing);
    });

    testWidgets('livre incohérent avec le solde : alerte rouge explicite', (tester) async {
      await ouvrir(tester, solde: 9999, mouvements: [
        _mouvement('1', MouvementPortefeuille.recharge, 5000, 5000),
      ]);
      expect(find.byKey(const ValueKey('incoherence')), findsOneWidget);
      expect(find.text('Livre de comptes cohérent'), findsNothing);
    });

    testWidgets('ajustement : un montant non nul est obligatoire', (tester) async {
      final service = await ouvrir(tester, solde: 1000, mouvements: const []);
      await remplir(tester, montant: '0', motif: 'test');
      await tester.tap(enregistrer);
      await tester.pump();
      expect(find.textContaining('montant entier non nul'), findsOneWidget);
      expect(service.ajustements, isEmpty);
    });

    testWidgets('ajustement : le motif est obligatoire', (tester) async {
      final service = await ouvrir(tester, solde: 1000, mouvements: const []);
      await remplir(tester, montant: '500', motif: '  ');
      await tester.tap(enregistrer);
      await tester.pump();
      expect(find.text('Indiquez le motif de l\'ajustement.'), findsOneWidget);
      expect(service.ajustements, isEmpty);
    });

    testWidgets('ajustement confirmé : envoyé au serveur avec le motif', (tester) async {
      final service = await ouvrir(tester, solde: 1000, mouvements: const []);
      await remplir(tester, montant: '-300', motif: 'erreur de saisie');
      await tester.tap(enregistrer);
      await tester.pumpAndSettle();
      expect(find.text('Débiter le portefeuille ?'), findsOneWidget);
      expect(service.ajustements, isEmpty); // rien avant la confirmation

      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      expect(service.ajustements, [(clientId: 'awa', montant: -300, motif: 'erreur de saisie')]);
      expect(find.text('Ajustement enregistré. Nouveau solde : ${formaterFcfa(700)}.'), findsOneWidget);
    });

    testWidgets('ajustement annulé à la confirmation : rien n\'est envoyé', (tester) async {
      final service = await ouvrir(tester, solde: 1000, mouvements: const []);
      await remplir(tester, montant: '+500', motif: 'geste commercial');
      await tester.tap(enregistrer);
      await tester.pumpAndSettle();
      expect(find.text('Créditer le portefeuille ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(service.ajustements, isEmpty);
    });

    testWidgets('refus du serveur (solde négatif, plafond) : son message est affiché', (tester) async {
      await ouvrir(
        tester,
        solde: 100,
        mouvements: const [],
        refus: ApiException('Le solde ne peut pas devenir négatif.'),
      );
      await remplir(tester, montant: '-5000', motif: 'test');
      await tester.tap(enregistrer);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      expect(find.text('Le solde ne peut pas devenir négatif.'), findsOneWidget);
    });
  });
}

/// Serveur factice du paiement par solde : pas de lien, la commande est
/// déjà payée quand le serveur répond.
class _ServeurSolde extends CourseService {
  _ServeurSolde({this.refus});

  final Exception? refus;
  final commande = StreamController<CommandePaiement?>();
  String? methodeRecue;
  int? prixRecu;
  String? commandeSuivie;

  @override
  Future<DemandePaiement> creerPaiement({
    required String type,
    required String adresseDepart,
    required String adresseArrivee,
    required int prixFcfa,
    required String methodePaiement,
    required PointsCourse points,
  }) async {
    methodeRecue = methodePaiement;
    prixRecu = prixFcfa;
    if (refus case final erreur?) throw erreur;
    return DemandePaiement(commandeId: 'k1', lienPaiement: null, prixFcfa: prixFcfa);
  }

  @override
  Stream<CommandePaiement?> streamCommande(String commandeId) {
    commandeSuivie = commandeId;
    return commande.stream;
  }
}
