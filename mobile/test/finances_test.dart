import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/utils/format_fcfa.dart';
import 'package:sprint/core/widgets/payment_method_selector.dart';
import 'package:sprint/core/widgets/payment_method_sheet.dart';
import 'package:sprint/features/admin/presentation/sections/admin_finances_section.dart';
import 'package:sprint/features/client/presentation/payment_processing_page.dart';
import 'package:sprint/features/conducteur/presentation/tabs/conducteur_gains_tab.dart';
import 'package:sprint/features/conducteur/presentation/widgets/course_active_bandeau.dart';
import 'package:sprint/features/conducteur/presentation/widgets/gains_barres_chart.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/finances/data/comptabilite.dart';
import 'package:sprint/features/finances/data/finance_service.dart';

// Dimanche 27/09/2026, 15 h (Dakar = UTC) ; la semaine commence le lundi 21.
final _maintenant = DateTime.utc(2026, 9, 27, 15);

/// Une course terminée, avec sa commission figée : celle du 15 % d'avant le
/// 13 octobre 2026 par défaut, celle du taux actuel (10 %) avec [auTauxActuel].
LigneCourse _ligne(
  String id,
  String chauffeur,
  int prix, {
  required String methode,
  required DateTime date,
  bool remboursee = false,
  bool auTauxActuel = false,
}) =>
    LigneCourse(
      courseId: id,
      chauffeurId: chauffeur,
      prixFcfa: prix,
      commissionFcfa: auTauxActuel ? Commission.de(prix) : Commission.historique(prix),
      methodePaiement: methode,
      date: date,
      remboursee: remboursee,
    );

/// La course "c" de Moussa (10 000 FCFA, déjà versée) remboursée au
/// client après un signalement.
final _avecRemboursement = [
  for (final c in _courses)
    c.courseId == 'c'
        ? _ligne('c', 'moussa', 10000, methode: 'WAVE', date: DateTime.utc(2026, 9, 18, 10), remboursee: true)
        : c,
];

Reglement _versement(String chauffeur, int montant) =>
    Reglement(id: 'r', chauffeurId: chauffeur, montantFcfa: montant, date: _maintenant);

// Courses d'avant le 13 octobre 2026 (commission figée de 15 %) : parts chauffeur de 2 550, 1 700, 8 500 et 3 400.
final _courses = [
  _ligne('a', 'moussa', 3000, methode: 'WAVE', date: DateTime.utc(2026, 9, 27, 9)), // aujourd'hui
  _ligne('b', 'moussa', 2000, methode: 'ORANGE_MONEY', date: DateTime.utc(2026, 9, 27, 11)), // aujourd'hui
  _ligne('c', 'moussa', 10000, methode: 'WAVE', date: DateTime.utc(2026, 9, 18, 10)), // semaine dernière
  _ligne('d', 'awa', 4000, methode: 'ORANGE_MONEY', date: DateTime.utc(2026, 9, 22, 10)), // mardi, même semaine
];

class _FinanceFactice extends FinanceService {
  _FinanceFactice({List<LigneCourse>? courses}) : courses = courses ?? _courses;

  final List<LigneCourse> courses;
  final reglements = <Reglement>[_versement('moussa', 10000)];
  final enregistres = <(String, int)>[];

  @override
  Stream<List<LigneCourse>> streamCoursesChauffeur(String chauffeurId) => Stream.value([
        for (final c in courses)
          if (c.chauffeurId == chauffeurId) c
      ]);

  @override
  Stream<List<Reglement>> streamReglementsChauffeur(String chauffeurId) => Stream.value([
        for (final r in reglements)
          if (r.chauffeurId == chauffeurId) r
      ]);

  @override
  Stream<Map<String, int>> streamTempsEnLigne(String chauffeurId) =>
      Stream.value({'2026-09-27': 3720, '2026-09-22': 7200});

  @override
  Stream<List<LigneCourse>> streamToutesCourses() => Stream.value(courses);

  @override
  Stream<List<Reglement>> streamTousReglements() => Stream.value(reglements);

  @override
  Future<void> enregistrerVersement({
    required String chauffeurId,
    required int montantFcfa,
    String? note,
  }) async =>
      enregistres.add((chauffeurId, montantFcfa));
}

void main() {
  group('Comptabilité (100 % mobile money)', () {
    test('commission de 10 % (décision du 13 octobre 2026), arrondie à l\'inférieur, comme les règles Firestore', () {
      expect(Commission.pourcentage, 10);
      expect(Commission.de(3000), 300);
      expect(Commission.de(3100), 310);
      expect(Commission.de(300), 30); // course minimum de province
      expect(Commission.de(1005), 100); // 100,5
    });

    test('l\'ancien taux de 15 % reste connu, pour les courses terminées avant le changement', () {
      expect(Commission.pourcentageHistorique, 15);
      expect(Commission.historique(3000), 450);
      expect(Commission.historique(3100), 465);
      expect(Commission.historique(1010), 151); // 151,5
    });

    test('course d\'avant le changement : Sprint doit 85 % au chauffeur, comme avant', () {
      expect(_courses[0].partChauffeurFcfa, 2550);
      expect(_courses[1].partChauffeurFcfa, 1700);
      expect(_courses[0].pourcentageCommission, 15);
    });

    test('course terminée au taux de 10 % : Sprint doit 90 % au chauffeur', () {
      final ligne = _ligne('n', 'moussa', 3100, methode: 'WAVE', date: DateTime.utc(2026, 10, 14, 9), auTauxActuel: true);
      expect(ligne.commissionFcfa, 310);
      expect(ligne.partChauffeurFcfa, 2790);
      expect(ligne.pourcentageCommission, 10);
      // Course minimum de province : 300 FCFA, dont 30 pour Sprint et 270 pour le chauffeur.
      final minimum = _ligne('m', 'moussa', 300, methode: 'WAVE', date: DateTime.utc(2026, 10, 14, 9), auTauxActuel: true);
      expect((minimum.commissionFcfa, minimum.partChauffeurFcfa), (30, 270));
    });

    test('taux affiché pour une période : celui de ses courses, aucun si elles n\'ont pas toutes le même', () {
      LigneCourse a(int jour, {required bool nouveau}) =>
          _ligne('x$jour', 'moussa', 2000, methode: 'WAVE', date: DateTime.utc(2026, 10, jour, 9), auTauxActuel: nouveau);
      final avant = a(12, nouveau: false);
      final apres = a(14, nouveau: true);
      final apresBis = a(15, nouveau: true);

      expect(Compte(courses: [avant]).pourcentageCommission, 15);
      expect(Compte(courses: [apres, apresBis]).pourcentageCommission, 10);
      expect(Compte(courses: [avant, apres]).pourcentageCommission, isNull, reason: 'période à cheval sur le changement');
      expect(Compte(courses: const []).pourcentageCommission, 10, reason: 'aucune course : le taux actuel');

      // Une course remboursée ne compte pas : seule une course payée donne le taux de la période.
      final avantRemboursee =
          _ligne('r', 'moussa', 2000, methode: 'WAVE', date: DateTime.utc(2026, 10, 12, 9), remboursee: true);
      expect(Compte(courses: [avantRemboursee, apres]).pourcentageCommission, 10);
      expect(Compte(courses: [avantRemboursee]).pourcentageCommission, 10);
    });

    test('une période à cheval sur le changement garde la commission exacte de chaque course', () {
      final avant = _ligne('a', 'moussa', 3000, methode: 'WAVE', date: DateTime.utc(2026, 10, 12, 9)); // 450
      final apres = _ligne('b', 'moussa', 3000, methode: 'WAVE', date: DateTime.utc(2026, 10, 14, 9), auTauxActuel: true); // 300
      final compte = Compte(courses: [avant, apres]);
      expect(compte.chiffreAffairesFcfa, 6000);
      expect(compte.commissionsFcfa, 750);
      expect(compte.gainsNetsFcfa, 5250);
    });

    test('ce que Sprint doit : part des courses moins les versements', () {
      final moussa = Compte(courses: _courses, reglements: [_versement('moussa', 10000)]).duChauffeur('moussa');
      expect(moussa.chiffreAffairesFcfa, 15000);
      expect(moussa.commissionsFcfa, 450 + 300 + 1500);
      expect(moussa.gainsNetsFcfa, 12750);
      expect(moussa.versementsFcfa, 10000);
      expect(moussa.soldeFcfa, 2750);

      final solde = Compte(courses: [_courses[1]], reglements: [_versement('moussa', 1700)]);
      expect(solde.soldeFcfa, 0);
    });

    test('périodes : jour et semaine (lundi) à l\'heure de Dakar', () {
      expect(Periodes.debutJour(_maintenant), DateTime.utc(2026, 9, 27));
      expect(Periodes.debutSemaine(_maintenant), DateTime.utc(2026, 9, 21));
      expect(Periodes.cleJour(_maintenant), '2026-09-27');
      final compte = Compte(courses: _courses).duChauffeur('moussa');
      expect(compte.depuis(Periodes.debutJour(_maintenant)).nombreCourses, 2);
      expect(compte.depuis(Periodes.debutSemaine(_maintenant)).chiffreAffairesFcfa, 5000);
    });

    CourseFirestore ancienne(String methode) => CourseFirestore(
          id: 'x',
          clientId: 'c',
          chauffeurId: 'moussa',
          statut: StatutCourse.terminee,
          type: 'PASSAGER',
          adresseDepart: 'A',
          adresseArrivee: 'B',
          prixFcfa: 2500,
          methodePaiement: methode,
          timestamp: DateTime.utc(2026, 9, 1),
        );

    test('course terminée avant la gestion financière (sans commission figée) : le taux d\'alors, 15 %', () {
      final ligne = LigneCourse.depuisCourse(ancienne('WAVE'));
      expect(ligne.commissionFcfa, 375);
      expect(ligne.partChauffeurFcfa, 2125);
      expect(ligne.libelleMethode, 'Wave');
      expect(ligne.date, DateTime.utc(2026, 9, 1));
    });

    test('ancienne course de test "ESPECES" : comptée comme due au chauffeur', () {
      expect(LigneCourse.depuisCourse(ancienne('ESPECES')).partChauffeurFcfa, 2125);
    });

    test('course remboursée au client : le chauffeur n\'est pas payé, déduit s\'il a déjà reçu sa part', () {
      final ligne = _avecRemboursement[2];
      expect(ligne.partChauffeurFcfa, 0);
      expect(ligne.partRetireeFcfa, 8500);
      expect(ligne.encaisseFcfa, 0);
      expect(ligne.commissionGagneeFcfa, 0);

      final moussa =
          Compte(courses: _avecRemboursement, reglements: [_versement('moussa', 10000)]).duChauffeur('moussa');
      expect(moussa.nombreCourses, 2);
      expect(moussa.nombreRemboursees, 1);
      expect(moussa.chiffreAffairesFcfa, 5000);
      expect(moussa.commissionsFcfa, 750);
      expect(moussa.gainsNetsFcfa, 4250);
      expect(moussa.partsRetireesFcfa, 8500);
      // Les 10 000 déjà versés dépassent ses gains : 5 750 à déduire.
      expect(moussa.soldeFcfa, -5750);

      // Sans versement préalable, la part n'est simplement jamais due.
      expect(Compte(courses: _avecRemboursement).duChauffeur('moussa').soldeFcfa, 4250);
    });

    test('remboursement lu sur la course (rembourseeLe), part retirée seulement si terminée', () {
      final terminee = CourseFirestore(
        id: 'x',
        clientId: 'awa',
        chauffeurId: 'moussa',
        adresseDepart: 'A',
        adresseArrivee: 'B',
        prixFcfa: 2300,
        methodePaiement: 'WAVE',
        type: 'COURSE',
        statut: StatutCourse.terminee,
        timestamp: DateTime.utc(2026, 9, 27),
        commissionFcfa: 345,
        rembourseeLe: DateTime.utc(2026, 9, 28),
      );
      expect(LigneCourse.depuisCourse(terminee).remboursee, isTrue);
      expect(LigneCourse.depuisCourse(terminee).partChauffeurFcfa, 0);
      expect(LigneCourse.partChauffeurDe(terminee), 1955);
    });

    test('la part du chauffeur se lit sur la commission figée de la course, jamais recalculée au taux du jour', () {
      CourseFirestore terminee(int commission) => CourseFirestore(
            id: 'x',
            clientId: 'awa',
            chauffeurId: 'moussa',
            adresseDepart: 'A',
            adresseArrivee: 'B',
            prixFcfa: 2300,
            methodePaiement: 'WAVE',
            type: 'COURSE',
            statut: StatutCourse.terminee,
            timestamp: DateTime.utc(2026, 10, 14),
            commissionFcfa: commission,
          );
      expect(LigneCourse.partChauffeurDe(terminee(230)), 2070); // figée à 10 %
      expect(LigneCourse.partChauffeurDe(terminee(345)), 1955); // figée à 15 %, avant le changement
      expect(LigneCourse.depuisCourse(terminee(230)).pourcentageCommission, 10);
      expect(LigneCourse.depuisCourse(terminee(345)).pourcentageCommission, 15);
    });

    test('temps en ligne lisible', () {
      expect(dureeEnLigne(0), '0 min');
      expect(dureeEnLigne(2700), '45 min');
      expect(dureeEnLigne(3720), '1 h 02');
    });
  });

  group('Client : Wave ou solde Sprint (Orange Money fermé)', () {
    test('aucun mode de paiement en espèces : mobile money, ou solde Sprint (rechargé par mobile money)', () {
      expect(PaymentMethod.values, [PaymentMethod.wave, PaymentMethod.orangeMoney, PaymentMethod.portefeuille]);
      expect(PaymentMethod.values.map((m) => m.apiValue), ['WAVE', 'ORANGE_MONEY', 'PORTEFEUILLE']);
    });

    test('Orange Money reste connu (historique) mais n\'est pas proposé : seul Wave est ouvert', () {
      expect(moyensMobileMoneyDisponibles, [PaymentMethod.wave]);
      expect(moyensMobileMoneyDisponibles, isNot(contains(PaymentMethod.orangeMoney)));
      expect(PaymentMethod.orangeMoney.label, 'Orange Money'); // libellé de l'historique conservé
    });

    testWidgets('la sheet ne propose que Wave : plus d\'Orange Money (course gratuite par la simulation)', (tester) async {
      PaymentMethod? choix;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choix = await afficherSelectionPaiementSheet(context, montantFcfa: 3000),
            child: const Text('Ouvrir'),
          ),
        ),
      ));
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Payer avec Wave'), findsOneWidget);
      expect(find.textContaining('Orange', findRichText: true), findsNothing);
      expect(find.textContaining('espèces', findRichText: true), findsNothing);
      expect(find.textContaining('Espèces', findRichText: true), findsNothing);
      await tester.tap(find.text('Payer avec Wave'));
      await tester.pumpAndSettle();
      expect(choix, PaymentMethod.wave);
    });

    testWidgets('course suivie seulement après confirmation du paiement par le serveur', (tester) async {
      final courses = _CourseServiceEspion();
      await tester.pumpWidget(MaterialApp(
        home: PaymentProcessingPage(
          methode: PaymentMethod.wave,
          type: 'PASSAGER',
          adresseDepart: 'Plateau',
          adresseArrivee: 'Almadies',
          prixFcfa: 3000,
          points: const PointsCourse(
            latitudeDepart: 14.668,
            longitudeDepart: -17.438,
            latitudeArrivee: 14.745,
            longitudeArrivee: -17.517,
          ),
          courseService: courses,
          ouvrirLien: (_) async => true,
        ),
      ));
      await tester.pump();
      expect(courses.methode, 'WAVE');
      await tester.tap(find.text('Payer avec Wave · ${formaterFcfa(3000)}'));
      await tester.pump();
      expect(find.text('En attente de la confirmation de\nvotre paiement Wave…'), findsOneWidget);
      expect(find.text('Paiement confirmé !'), findsNothing);

      courses.commande.add(const CommandePaiement(statut: StatutCommande.payee, courseId: 'course-test'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Paiement confirmé !'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      // L'écran suivant (SuiviCoursePage) écoute Firestore, absent des tests.
      tester.takeException();
    });
  });

  group('Chauffeur : onglet Gains', () {
    Future<void> afficher(WidgetTester tester, _FinanceFactice service, {DateTime? maintenant}) async {
      tester.view.physicalSize = const Size(430, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ConducteurGainsTab(service: service, chauffeurId: 'moussa', maintenant: maintenant ?? _maintenant),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('ce que Sprint doit, gains du jour et de la semaine, versements', (tester) async {
      await afficher(tester, _FinanceFactice());

      expect(find.text('Sprint vous doit'), findsOneWidget);
      expect(find.text(formaterFcfa(2750)), findsOneWidget); // 12 750 - 10 000 versés
      expect(find.text('2 courses · 1 h 02 en ligne'), findsOneWidget); // aujourd'hui
      expect(find.text('2 courses · 3 h 02 en ligne'), findsOneWidget); // semaine : + 2 h le mardi
      expect(find.text(formaterFcfa(4250)), findsNWidgets(2)); // gains du jour et de la semaine
      expect(find.text(formaterFcfa(5000)), findsOneWidget); // payé par les clients (semaine)
      expect(find.text('− ${formaterFcfa(750)}'), findsOneWidget); // commission de la semaine
      expect(find.text('+${formaterFcfa(2550)}'), findsOneWidget); // part d'une course
      expect(find.text('Payée par Orange Money'), findsOneWidget);
      expect(find.text('27/09 · Reçu de Sprint'), findsOneWidget);
      expect(find.textContaining('Vous devez'), findsNothing);
      expect(find.textContaining('spèces'), findsNothing);
      // Les courses de la semaine datent d'avant le changement de taux : leur 15 % est écrit tel quel.
      expect(find.text('Commission Sprint (15 %)'), findsOneWidget);
      expect(find.text('Vos gains (85 %)'), findsOneWidget);
      expect(
        find.text('Votre part de vos courses payées en mobile money (le prix moins la commission de Sprint), '
            'moins les versements déjà reçus.'),
        findsOneWidget,
      );
    });

    // Jeudi 22/10/2026, 15 h : la semaine commence le lundi 19, après le passage à 10 %.
    final jeudi22 = DateTime.utc(2026, 10, 22, 15);
    // Jeudi 15/10/2026, 15 h : la semaine commence le lundi 12, avant et après le passage à 10 %.
    final jeudi15 = DateTime.utc(2026, 10, 15, 15);

    testWidgets('courses au taux actuel : 10 % pour Sprint, 90 % pour le chauffeur, plus aucune trace de 15 %',
        (tester) async {
      final service = _FinanceFactice(courses: [
        _ligne('n1', 'moussa', 3100, methode: 'WAVE', date: DateTime.utc(2026, 10, 19, 10), auTauxActuel: true), // 310
        _ligne('n2', 'moussa', 2000, methode: 'WAVE', date: DateTime.utc(2026, 10, 22, 9), auTauxActuel: true), // 200
      ])
        ..reglements.clear();
      await afficher(tester, service, maintenant: jeudi22);

      expect(find.text('Commission Sprint (10 %)'), findsOneWidget);
      expect(find.text('Vos gains (90 %)'), findsOneWidget);
      expect(find.text(formaterFcfa(5100)), findsOneWidget); // payé par les clients (semaine)
      expect(find.text('− ${formaterFcfa(510)}'), findsOneWidget); // commission de la semaine : 310 + 200
      expect(find.text(formaterFcfa(4590)), findsNWidgets(2)); // gains de la semaine, et ce que Sprint doit
      expect(find.text(formaterFcfa(1800)), findsOneWidget); // gains du jour : 2 000 - 200
      expect(find.text('+${formaterFcfa(2790)}'), findsOneWidget); // part d'une course : 3 100 - 310
      expect(find.textContaining('15 %'), findsNothing);
      expect(find.textContaining('85 %'), findsNothing);
    });

    testWidgets('semaine à cheval sur le changement de taux : aucun pourcentage faux, chaque course garde sa part',
        (tester) async {
      final service = _FinanceFactice(courses: [
        _ligne('a', 'moussa', 3000, methode: 'WAVE', date: DateTime.utc(2026, 10, 12, 10)), // 15 % : 450
        _ligne('b', 'moussa', 2000, methode: 'WAVE', date: DateTime.utc(2026, 10, 15, 9), auTauxActuel: true), // 10 % : 200
      ])
        ..reglements.clear();
      await afficher(tester, service, maintenant: jeudi15);

      expect(find.text('Commission Sprint'), findsOneWidget);
      expect(find.text('Vos gains'), findsNWidgets(2)); // du jour, et de la semaine
      expect(find.textContaining('Commission Sprint ('), findsNothing);
      expect(find.textContaining('Vos gains ('), findsNothing);
      expect(find.text('− ${formaterFcfa(650)}'), findsOneWidget); // 450 + 200
      expect(find.text(formaterFcfa(4350)), findsNWidgets(2)); // gains de la semaine, et ce que Sprint doit
      expect(find.text('+${formaterFcfa(2550)}'), findsOneWidget); // la course de 15 % garde sa part de 85 %
      expect(find.text('+${formaterFcfa(1800)}'), findsOneWidget); // celle de 10 % a sa part de 90 %
    });

    testWidgets('tout versé : aucune somme en attente, jamais de dette', (tester) async {
      final service = _FinanceFactice()..reglements.add(_versement('moussa', 2750));
      await afficher(tester, service);
      expect(find.text(formaterFcfa(0)), findsOneWidget);
      expect(find.text('Aucune somme en attente : tout vous a été versé.'), findsOneWidget);
      expect(find.textContaining('Vous devez'), findsNothing);
    });

    testWidgets('course remboursée : non payée, montant déjà versé déduit des prochains gains', (tester) async {
      await afficher(tester, _FinanceFactice(courses: _avecRemboursement));
      expect(find.text(formaterFcfa(0)), findsNWidgets(2)); // carte "Sprint vous doit" et ligne remboursée
      expect(
        find.text('${formaterFcfa(5750)} seront déduits de vos prochains gains : une course déjà '
            'versée a été remboursée au client.'),
        findsOneWidget,
      );
      expect(find.text('Remboursée au client'), findsOneWidget);
      expect(find.text('18/09 · suite à un signalement, non payée'), findsOneWidget);
      expect(find.text('+${formaterFcfa(8500)}'), findsNothing);
      expect(find.textContaining('Vous devez'), findsNothing);
    });

    testWidgets('semaine sans recette : le graphique ne plante pas', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: GainsBarresChart(valeurs: [0, 0, 0, 0, 0, 0, 0], labels: ['L', 'M', 'M', 'J', 'V', 'S', 'D'])),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('Admin : Finances', () {
    Future<void> afficher(WidgetTester tester, _FinanceFactice service) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminFinancesSection(
              service: service,
              noms: Stream.value(const {'moussa': 'Moussa Diop', 'awa': 'Awa Ndiaye'}),
              maintenant: _maintenant,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('CA, commissions, reste à verser et saisie d\'un versement plafonné', (tester) async {
      final service = _FinanceFactice();
      await afficher(tester, service);

      expect(find.text(formaterFcfa(19000)), findsOneWidget); // CA total
      expect(find.text(formaterFcfa(9000)), findsOneWidget); // CA semaine
      expect(find.text(formaterFcfa(2850)), findsOneWidget); // commissions totales
      expect(find.text(formaterFcfa(10000)), findsOneWidget); // versé aux chauffeurs
      expect(find.text(formaterFcfa(6150)), findsOneWidget); // reste à verser : 3 400 + 2 750
      expect(find.text(formaterFcfa(3400)), findsOneWidget); // Awa
      expect(find.text(formaterFcfa(2750)), findsOneWidget); // Moussa
      expect(find.textContaining('Dû par'), findsNothing);
      expect(find.textContaining('spèces'), findsNothing);
      // Le texte dit le taux d'aujourd'hui, et que les courses déjà terminées gardent le leur.
      expect(find.textContaining('Commission : 10 % de chaque course terminée'), findsOneWidget);
      expect(find.textContaining('gardent leurs 15 %'), findsOneWidget);
      expect(find.textContaining('85 %'), findsNothing);

      // Awa en tête (Sprint lui doit le plus).
      await tester.tap(find.widgetWithText(OutlinedButton, 'Verser').first);
      await tester.pumpAndSettle();
      expect(find.text('Versement à Awa Ndiaye'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '3400'), '5000');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('Sprint ne doit que ${formaterFcfa(3400)} à Awa Ndiaye.'), findsOneWidget);
      expect(service.enregistres, isEmpty);

      await tester.enterText(find.widgetWithText(TextField, '5000'), '3400');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(service.enregistres, [('awa', 3400)]);
      expect(find.text('Versement enregistré pour Awa Ndiaye.'), findsOneWidget);
    });

    testWidgets('course remboursée : exclue du CA et des commissions, part du chauffeur à déduire', (tester) async {
      await afficher(tester, _FinanceFactice(courses: _avecRemboursement));
      expect(find.text(formaterFcfa(9000)), findsNWidgets(2)); // CA total = CA semaine (19 000 - 10 000)
      expect(find.text(formaterFcfa(1350)), findsOneWidget); // commissions : 2 850 - 1 500
      expect(find.text(formaterFcfa(3400)), findsNWidgets(2)); // reste à verser = Awa seule
      expect(find.text('− ${formaterFcfa(5750)} à déduire'), findsOneWidget); // Moussa
      expect(find.widgetWithText(OutlinedButton, 'Verser'), findsOneWidget); // Awa seulement
      expect(
        find.textContaining('1 course(s) remboursée(s) au client, exclue(s) des comptes : part des chauffeurs '
            'retirée (${formaterFcfa(8500)}).'),
        findsOneWidget,
      );
    });

    testWidgets('chauffeur entièrement payé : "À jour", pas de bouton Verser', (tester) async {
      final service = _FinanceFactice()..reglements.add(_versement('awa', 3400));
      await afficher(tester, service);
      expect(find.text('À jour'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Verser'), findsOneWidget); // Moussa seulement
    });
  });

  testWidgets('bandeau : course déjà payée, rien à encaisser', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: CourseActiveBandeau(
          course: CourseFirestore(
            id: 'c',
            clientId: 'awa',
            chauffeurId: 'moussa',
            statut: StatutCourse.enCours,
            type: 'PASSAGER',
            adresseDepart: 'Plateau',
            adresseArrivee: 'Almadies',
            prixFcfa: 3000,
            methodePaiement: 'WAVE',
            timestamp: _maintenant,
          ),
          enCours: false,
          onAvancer: () {},
          onAppeler: () {},
          onMessage: () {},
          onNaviguer: () {},
          onAnnuler: () {},
        ),
      ),
    ));
    expect(find.text('Déjà payé par Wave'), findsOneWidget);
    expect(find.textContaining('encaisser'), findsNothing);
  });
}

class _CourseServiceEspion extends CourseService {
  String? methode;
  final commande = StreamController<CommandePaiement?>();

  @override
  Future<DemandePaiement> creerPaiement({
    required String type,
    required String adresseDepart,
    required String adresseArrivee,
    required int prixFcfa,
    required String methodePaiement,
    required PointsCourse points,
  }) async {
    methode = methodePaiement;
    return DemandePaiement(commandeId: 'k1', lienPaiement: Uri.parse('https://paiement.test/k1'), prixFcfa: prixFcfa);
  }

  @override
  Stream<CommandePaiement?> streamCommande(String commandeId) => commande.stream;
}
