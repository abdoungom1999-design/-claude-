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

LigneCourse _ligne(
  String id,
  String chauffeur,
  int prix, {
  required String methode,
  required DateTime date,
  bool remboursee = false,
}) =>
    LigneCourse(
      courseId: id,
      chauffeurId: chauffeur,
      prixFcfa: prix,
      commissionFcfa: Commission.de(prix),
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

// Parts chauffeur (85 %) : 2 550, 1 700, 8 500 et 3 400.
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
    test('commission 15 % arrondie à l\'inférieur, comme les règles Firestore', () {
      expect(Commission.de(3000), 450);
      expect(Commission.de(3100), 465);
      expect(Commission.de(1010), 151); // 151,5
    });

    test('chaque course : Sprint doit 85 % au chauffeur', () {
      expect(_courses[0].partChauffeurFcfa, 2550);
      expect(_courses[1].partChauffeurFcfa, 1700);
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

    test('course terminée avant la gestion financière : même commission', () {
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
    Future<void> afficher(WidgetTester tester, _FinanceFactice service) async {
      tester.view.physicalSize = const Size(430, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ConducteurGainsTab(service: service, chauffeurId: 'moussa', maintenant: _maintenant),
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
