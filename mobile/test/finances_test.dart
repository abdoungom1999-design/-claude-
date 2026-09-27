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
import 'package:sprint/features/paiement/data/paiement_service.dart';

// Dimanche 27/09/2026, 15 h (Dakar = UTC) ; la semaine commence le lundi 21.
final _maintenant = DateTime.utc(2026, 9, 27, 15);

LigneCourse _ligne(String id, String chauffeur, int prix, {required bool especes, required DateTime date}) =>
    LigneCourse(
      courseId: id,
      chauffeurId: chauffeur,
      prixFcfa: prix,
      commissionFcfa: Commission.de(prix),
      especes: especes,
      date: date,
    );

Reglement _reglement(String chauffeur, int montant, String sens) =>
    Reglement(id: 'r', chauffeurId: chauffeur, montantFcfa: montant, sens: sens, date: _maintenant);

final _courses = [
  _ligne('a', 'moussa', 3000, especes: true, date: DateTime.utc(2026, 9, 27, 9)), // aujourd'hui
  _ligne('b', 'moussa', 2000, especes: false, date: DateTime.utc(2026, 9, 27, 11)), // aujourd'hui
  _ligne('c', 'moussa', 10000, especes: true, date: DateTime.utc(2026, 9, 18, 10)), // semaine dernière
  _ligne('d', 'awa', 4000, especes: false, date: DateTime.utc(2026, 9, 22, 10)), // mardi, même semaine
];

class _FinanceFactice extends FinanceService {
  final reglements = <Reglement>[_reglement('moussa', 1000, SensReglement.chauffeurVersPlateforme)];
  final enregistres = <(String, int, String)>[];

  @override
  Stream<List<LigneCourse>> streamCoursesChauffeur(String chauffeurId) =>
      Stream.value([for (final c in _courses) if (c.chauffeurId == chauffeurId) c]);

  @override
  Stream<List<Reglement>> streamReglementsChauffeur(String chauffeurId) =>
      Stream.value([for (final r in reglements) if (r.chauffeurId == chauffeurId) r]);

  @override
  Stream<Map<String, int>> streamTempsEnLigne(String chauffeurId) =>
      Stream.value({'2026-09-27': 3720, '2026-09-22': 7200});

  @override
  Stream<List<LigneCourse>> streamToutesCourses() => Stream.value(_courses);

  @override
  Stream<List<Reglement>> streamTousReglements() => Stream.value(reglements);

  @override
  Future<void> enregistrerReglement({
    required String chauffeurId,
    required int montantFcfa,
    required String sens,
    String? note,
  }) async =>
      enregistres.add((chauffeurId, montantFcfa, sens));
}

void main() {
  group('Comptabilité', () {
    test('commission 15 % arrondie à l\'inférieur, comme les règles Firestore', () {
      expect(Commission.de(3000), 450);
      expect(Commission.de(3100), 465);
      expect(Commission.de(1010), 151); // 151,5
    });

    test('espèces : le chauffeur doit la commission ; mobile money : la plateforme doit 85 %', () {
      expect(_courses[0].effetSoldeFcfa, -450);
      expect(_courses[1].effetSoldeFcfa, 1700);
    });

    test('solde net après compensation et règlements', () {
      final moussa = Compte(courses: _courses, reglements: [_reglement('moussa', 1000, SensReglement.chauffeurVersPlateforme)])
          .duChauffeur('moussa');
      // -450 + 1 700 - 1 500 + 1 000 (versement du chauffeur)
      expect(moussa.soldeFcfa, 750);
      expect(sensDuSolde(moussa.soldeFcfa), SensSolde.plateformeDoit);
      expect(moussa.chiffreAffairesFcfa, 15000);
      expect(moussa.commissionsFcfa, 450 + 300 + 1500);
      expect(moussa.gainsNetsFcfa, 15000 - 2250);
      expect(moussa.especesFcfa, 13000);
      expect(moussa.mobileMoneyFcfa, 2000);

      final remboursement = Compte(courses: [_courses[1]], reglements: [_reglement('moussa', 1700, SensReglement.plateformeVersChauffeur)]);
      expect(sensDuSolde(remboursement.soldeFcfa), SensSolde.equilibre);
    });

    test('périodes : jour et semaine (lundi) à l\'heure de Dakar', () {
      expect(Periodes.debutJour(_maintenant), DateTime.utc(2026, 9, 27));
      expect(Periodes.debutSemaine(_maintenant), DateTime.utc(2026, 9, 21));
      expect(Periodes.cleJour(_maintenant), '2026-09-27');
      final compte = Compte(courses: _courses).duChauffeur('moussa');
      expect(compte.depuis(Periodes.debutJour(_maintenant)).nombreCourses, 2);
      expect(compte.depuis(Periodes.debutSemaine(_maintenant)).chiffreAffairesFcfa, 5000);
    });

    test('course terminée avant la gestion financière : même commission', () {
      final ancienne = LigneCourse.depuisCourse(CourseFirestore(
        id: 'x',
        clientId: 'c',
        chauffeurId: 'moussa',
        statut: StatutCourse.terminee,
        type: 'PASSAGER',
        adresseDepart: 'A',
        adresseArrivee: 'B',
        prixFcfa: 2500,
        methodePaiement: 'WAVE',
        timestamp: DateTime.utc(2026, 9, 1),
      ));
      expect(ancienne.commissionFcfa, 375);
      expect(ancienne.especes, isFalse);
      expect(ancienne.date, DateTime.utc(2026, 9, 1));
    });

    test('temps en ligne lisible', () {
      expect(dureeEnLigne(0), '0 min');
      expect(dureeEnLigne(2700), '45 min');
      expect(dureeEnLigne(3720), '1 h 02');
    });
  });

  group('Client : paiement en espèces', () {
    test('rien à encaisser dans l\'app', () async {
      final resultat = await const PaiementServiceSandbox(delai: Duration.zero).initierPaiement(PaymentMethod.especes, 3000);
      expect(resultat.estReussie, isTrue);
      expect(PaymentMethod.especes.apiValue, 'ESPECES');
    });

    testWidgets('choix "Espèces" proposé avec Wave et Orange Money', (tester) async {
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
      expect(find.text('Payer avec Orange Money'), findsOneWidget);
      await tester.tap(find.text('Payer en espèces au chauffeur'));
      await tester.pumpAndSettle();
      expect(choix, PaymentMethod.especes);
    });

    testWidgets('commande en espèces : course créée avec ESPECES, sans paiement', (tester) async {
      final courses = _CourseServiceEspion();
      await tester.pumpWidget(MaterialApp(
        home: PaymentProcessingPage(
          methode: PaymentMethod.especes,
          clientId: 'awa',
          type: 'PASSAGER',
          adresseDepart: 'Plateau',
          adresseArrivee: 'Almadies',
          prixFcfa: 3000,
          courseService: courses,
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Commande confirmée !'), findsOneWidget);
      expect(find.text('Vous réglerez ${formaterFcfa(3000)} en espèces au chauffeur.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(courses.methode, 'ESPECES');
      // L'écran suivant (SuiviCoursePage) écoute Firestore, absent des tests.
      tester.takeException();
    });
  });

  group('Chauffeur : onglet Gains', () {
    testWidgets('CA du jour et de la semaine, temps en ligne, solde et détail', (tester) async {
      tester.view.physicalSize = const Size(430, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ConducteurGainsTab(service: _FinanceFactice(), chauffeurId: 'moussa', maintenant: _maintenant),
      ));
      await tester.pumpAndSettle();

      expect(find.text(formaterFcfa(5000)), findsWidgets); // CA du jour
      expect(find.text('2 courses · 1 h 02 en ligne'), findsOneWidget);
      expect(find.text('${formaterFcfa(5000)} · 2 courses · 3 h 02 en ligne'), findsOneWidget); // + 2 h le mardi
      expect(find.text('Sprint vous doit ${formaterFcfa(750)}'), findsOneWidget);
      expect(find.text('− ${formaterFcfa(750)}'), findsOneWidget); // commission de la semaine
      expect(find.text(formaterFcfa(4250)), findsOneWidget); // gains nets de la semaine
      expect(find.textContaining('Versé à Sprint'), findsOneWidget);
    });

    testWidgets('chauffeur qui doit de l\'argent', (tester) async {
      final service = _FinanceFactice()..reglements.clear();
      tester.view.physicalSize = const Size(430, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ConducteurGainsTab(service: service, chauffeurId: 'moussa', maintenant: _maintenant),
      ));
      await tester.pumpAndSettle();
      // -450 + 1 700 - 1 500
      expect(find.text('Vous devez ${formaterFcfa(250)} à Sprint'), findsOneWidget);
    });

    testWidgets('semaine sans recette : le graphique ne plante pas', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: GainsBarresChart(valeurs: [0, 0, 0, 0, 0, 0, 0], labels: ['L', 'M', 'M', 'J', 'V', 'S', 'D'])),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('Admin : Finances', () {
    testWidgets('CA de la plateforme, soldes par chauffeur et saisie d\'un règlement', (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _FinanceFactice();
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

      expect(find.text(formaterFcfa(19000)), findsOneWidget); // CA total
      expect(find.text(formaterFcfa(9000)), findsOneWidget); // CA semaine
      expect(find.text(formaterFcfa(2850)), findsOneWidget); // commissions totales
      expect(find.text('À reverser ${formaterFcfa(3400)}'), findsOneWidget); // Awa : 4 000 - 600
      expect(find.text('À reverser ${formaterFcfa(750)}'), findsOneWidget); // Moussa

      await tester.tap(find.widgetWithText(OutlinedButton, 'Règlement').first);
      await tester.pumpAndSettle();
      expect(find.text('Règlement : Awa Ndiaye'), findsOneWidget);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(service.enregistres, [('awa', 3400, SensReglement.plateformeVersChauffeur)]);
      expect(find.text('Règlement enregistré pour Awa Ndiaye.'), findsOneWidget);
    });
  });

  testWidgets('bandeau : rappel du montant à encaisser en espèces', (tester) async {
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
            methodePaiement: 'ESPECES',
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
    expect(find.text('Espèces : ${formaterFcfa(3000)} à encaisser'), findsOneWidget);
  });
}

class _CourseServiceEspion extends CourseService {
  String? methode;

  @override
  Future<String> creerCourse({
    required String clientId,
    required String type,
    required String adresseDepart,
    required String adresseArrivee,
    required int prixFcfa,
    required String methodePaiement,
    required String transactionId,
    PointsCourse? points,
  }) async {
    methode = methodePaiement;
    return 'course-test';
  }
}
