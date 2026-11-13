import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/utils/format_fcfa.dart';
import 'package:sprint/features/admin/presentation/sections/admin_finances_section.dart';
import 'package:sprint/features/conducteur/presentation/tabs/conducteur_gains_tab.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/finances/data/argent_de_test.dart';
import 'package:sprint/features/finances/data/comptabilite.dart';
import 'package:sprint/features/finances/data/finance_service.dart';
import 'package:sprint/features/portefeuille/data/portefeuille_service.dart';
import 'package:sprint/features/portefeuille/presentation/mouvements_portefeuille_page.dart';

// Argent de test (décision du client, 13 novembre 2026) : le faux Wave ne débite personne, ce qu'il produit
// est marqué « argent de test » par le serveur et ne doit jamais entrer dans la comptabilité.

// Vendredi 13/11/2026, 15 h (Dakar = UTC) ; la semaine commence le lundi 9.
final _maintenant = DateTime.utc(2026, 11, 13, 15);

Map<String, dynamic> _document({Map<String, dynamic> extra = const {}, DateTime? date}) => {
      'clientId': 'awa',
      'chauffeurId': 'moussa',
      'statut': 'terminee',
      'type': 'PASSAGER',
      'adresseDepart': 'Plateau',
      'adresseArrivee': 'Almadies',
      'prixFcfa': 2300,
      'methodePaiement': 'WAVE',
      'timestamp': Timestamp.fromDate(date ?? DateTime.utc(2026, 11, 13, 12)),
      ...extra,
    };

LigneCourse _ligne(
  String id,
  int prix, {
  String chauffeur = 'moussa',
  bool test = false,
  bool remboursee = false,
  DateTime? date,
}) =>
    LigneCourse(
      courseId: id,
      chauffeurId: chauffeur,
      prixFcfa: prix,
      commissionFcfa: Commission.de(prix),
      methodePaiement: test ? 'WAVE' : 'ORANGE_MONEY',
      date: date ?? DateTime.utc(2026, 11, 13, 10),
      remboursee: remboursee,
      argentDeTest: test,
    );

class _FinanceFactice extends FinanceService {
  _FinanceFactice(this.courses);

  final List<LigneCourse> courses;

  @override
  Stream<List<LigneCourse>> streamCoursesChauffeur(String chauffeurId) =>
      Stream.value([for (final c in courses) if (c.chauffeurId == chauffeurId) c]);

  @override
  Stream<List<Reglement>> streamReglementsChauffeur(String chauffeurId) => Stream.value(const []);

  @override
  Stream<Map<String, int>> streamTempsEnLigne(String chauffeurId) => Stream.value(const {});

  @override
  Stream<List<LigneCourse>> streamToutesCourses() => Stream.value(courses);

  @override
  Stream<List<Reglement>> streamTousReglements() => Stream.value(const []);
}

class _PortefeuilleFactice extends PortefeuilleService {
  _PortefeuilleFactice(this.mouvements);

  final List<MouvementPortefeuille> mouvements;

  @override
  Stream<List<MouvementPortefeuille>> streamMouvements(String uid) => Stream.value(mouvements);
}

void main() {
  group('Argent de test : marque d\'une course', () {
    test('une course créée avant le marquage est jugée sur son moyen de paiement et sa date', () {
      final avant = DateTime.utc(2026, 11, 2, 9, 42);
      final depuis = DateTime.utc(2026, 11, 2, 9, 43);
      // Jumeau de DEBUT_ARGENT_REEL_ORANGE du serveur (un test du serveur compare les deux).
      expect(debutArgentReelOrange, depuis);

      bool test(String methode, DateTime date) => courseSansMarqueEnArgentDeTest(methodePaiement: methode, date: date);
      expect(test('WAVE', depuis), isTrue, reason: 'le seul Wave de l\'époque est le faux Wave');
      expect(test('ORANGE_MONEY', avant), isTrue, reason: 'bac à sable d\'Orange');
      expect(test('ORANGE_MONEY', depuis), isFalse, reason: 'Orange Money en production : argent réel');
      expect(test('PORTEFEUILLE', depuis), isTrue, reason: 'origine de l\'argent non enregistrée : prudence');
      for (final autre in ['ESPECES', 'CARTE', '']) {
        expect(test(autre, depuis), isFalse, reason: '$autre : comptée comme avant');
      }
    });

    test('la marque du serveur fait foi ; absente ou illisible, le moyen de paiement décide', () {
      CourseFirestore lire(Map<String, dynamic> extra) => CourseFirestore.depuisDocument('c', _document(extra: extra));

      expect(lire({}).argentDeTest, isTrue, reason: 'ancienne course Wave');
      expect(lire({'argentDeTest': true}).argentDeTest, isTrue);
      expect(lire({'argentDeTest': false}).argentDeTest, isFalse, reason: 'la marque du serveur fait foi');
      expect(lire({'argentDeTest': false, 'methodePaiement': 'WAVE'}).argentDeTest, isFalse);
      expect(lire({'argentDeTest': true, 'methodePaiement': 'ORANGE_MONEY'}).argentDeTest, isTrue);
      for (final illisible in ['oui', 1, null]) {
        expect(lire({'argentDeTest': illisible}).argentDeTest, isTrue, reason: '$illisible : comme sans marque');
      }
      expect(lire({'methodePaiement': 'ORANGE_MONEY'}).argentDeTest, isFalse, reason: 'ancienne course Orange en production');
      // Le radar, qui reprend les champs de la course, porte la même marque.
      expect(CourseFirestore.depuisDocument('r', {..._document(), 'argentDeTest': true, 'statut': 'en_attente'}).argentDeTest, isTrue);
    });

    test('le libellé du paiement dit « argent de test » ; la marque suit la course quand la position exacte arrive', () {
      final test = CourseFirestore.depuisDocument(
        'c',
        _document(extra: {'argentDeTest': true, 'latitudeDepart': 14.69, 'longitudeDepart': -17.44, 'latitudeArrivee': 14.74, 'longitudeArrivee': -17.51}),
      );
      expect(test.libellePaiement, 'Déjà payé par Wave');
      expect(test.libellePaiementMarque, 'Déjà payé par Wave · argent de test');
      expect(test.avecDepartExact(const DepartExact(latitude: 14.6925, longitude: -17.4468)).argentDeTest, isTrue);

      final reel = CourseFirestore.depuisDocument('c', _document(extra: {'argentDeTest': false, 'methodePaiement': 'ORANGE_MONEY'}));
      expect(reel.libellePaiementMarque, 'Déjà payé par Orange Money');
    });

    test('mouvement du portefeuille : la marque du serveur est lue, absente = argent réel', () {
      final recharge = MouvementPortefeuille.depuisDocument('m', {'type': 'recharge', 'montantFcfa': 5000, 'argentDeTest': true});
      expect(recharge.argentDeTest, isTrue);
      expect(MouvementPortefeuille.depuisDocument('m', {'type': 'recharge', 'montantFcfa': 5000}).argentDeTest, isFalse);
      expect(MouvementPortefeuille.depuisDocument('m', {'type': 'recharge', 'argentDeTest': 'oui'}).argentDeTest, isFalse);
    });
  });

  group('Argent de test : jamais dans la comptabilité', () {
    test('une course en argent de test ne rapporte ni chiffre d\'affaires, ni commission, ni part au chauffeur', () {
      final test = _ligne('t', 2000, test: true);
      expect(test.compte, isFalse);
      expect(test.encaisseFcfa, 0);
      expect(test.commissionGagneeFcfa, 0);
      expect(test.partChauffeurFcfa, 0);
      // Visible quand même : le prix reste lisible.
      expect(test.prixFcfa, 2000);
      // Remboursée aussi : le chauffeur n'avait rien reçu, rien à lui retirer.
      final remboursee = _ligne('tr', 1000, test: true, remboursee: true);
      expect(remboursee.partRetireeFcfa, 0);
      expect(remboursee.partChauffeurFcfa, 0);
      // Une course réelle remboursée, elle, retire toujours la part déjà versée.
      expect(_ligne('rr', 1000, remboursee: true).partRetireeFcfa, 900);
    });

    test('compte : seul l\'argent réel est compté, l\'argent de test est dénombré à part', () {
      final compte = Compte(courses: [
        _ligne('r1', 3000),
        _ligne('r2', 1000, remboursee: true),
        _ligne('t1', 2000, test: true),
        _ligne('t2', 500, test: true, remboursee: true),
      ]);
      expect(compte.nombreCourses, 1);
      expect(compte.chiffreAffairesFcfa, 3000);
      expect(compte.commissionsFcfa, 300);
      expect(compte.gainsNetsFcfa, 2700);
      expect(compte.soldeFcfa, 2700, reason: 'Sprint ne doit au chauffeur que sa part des courses en argent réel');
      expect(compte.nombreRemboursees, 1, reason: 'seul le remboursement d\'une course réelle compte');
      expect(compte.partsRetireesFcfa, 900);
      expect(compte.nombreCoursesDeTest, 2);
      expect(compte.montantDeTestFcfa, 2500);
      // L'activité compte toutes les courses terminées non remboursées, réelles ou de test.
      expect(compte.nombreCoursesTerminees, 2);

      final seulementTest = Compte(courses: [_ligne('t', 2000, test: true)]);
      expect((seulementTest.chiffreAffairesFcfa, seulementTest.commissionsFcfa, seulementTest.soldeFcfa), (0, 0, 0));
      expect(seulementTest.pourcentageCommission, Commission.pourcentage);
    });

    test('part du chauffeur lue sur la course : nulle pour de l\'argent de test', () {
      CourseFirestore terminee({required bool test}) => CourseFirestore.depuisDocument(
            'c',
            _document(extra: {'argentDeTest': test, 'commissionFcfa': 230}),
          );
      expect(LigneCourse.partChauffeurDe(terminee(test: false)), 2070);
      expect(LigneCourse.partChauffeurDe(terminee(test: true)), 0);
      expect(LigneCourse.depuisCourse(terminee(test: true)).argentDeTest, isTrue);
      expect(LigneCourse.depuisCourse(terminee(test: false)).argentDeTest, isFalse);
    });
  });

  group('Argent de test : écrans', () {
    testWidgets('Admin, Finances : l\'argent de test est exclu de tous les chiffres, montré à part, et un chauffeur sans course réelle n\'a rien à se faire verser',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminFinancesSection(
              service: _FinanceFactice([
                _ligne('r', 3000), // moussa, argent réel
                _ligne('t1', 2000, test: true), // moussa, test
                _ligne('t2', 4000, chauffeur: 'awa', test: true), // awa : que du test
              ]),
              noms: Stream.value(const {'moussa': 'Moussa Diop', 'awa': 'Awa Ndiaye'}),
              maintenant: _maintenant,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('CA total'), findsOneWidget);
      expect(find.text(formaterFcfa(3000)), findsWidgets); // CA : la seule course réelle
      expect(find.text(formaterFcfa(300)), findsNWidgets(2)); // commissions : tuile du total et ligne de Moussa
      expect(find.text(formaterFcfa(2700)), findsWidgets); // reste à verser à Moussa
      // L'argent de test : 2 000 + 4 000, visible, à part.
      expect(find.text('Argent de test (non compté)'), findsOneWidget);
      expect(find.text(formaterFcfa(6000)), findsOneWidget);
      expect(find.textContaining('2 course(s) en argent de test'), findsOneWidget);
      expect(find.textContaining('jamais encaissés'), findsOneWidget);
      // Awa n'a fait que des courses de test : pas de ligne dans « À verser aux chauffeurs ».
      expect(find.text('Moussa Diop'), findsOneWidget);
      expect(find.text('Awa Ndiaye'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Admin, Finances : sans argent de test, ni tuile ni mention', (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminFinancesSection(
              service: _FinanceFactice([_ligne('r', 3000)]),
              noms: Stream.value(const {'moussa': 'Moussa Diop'}),
              maintenant: _maintenant,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Argent de test (non compté)'), findsNothing);
      expect(find.textContaining('en argent de test'), findsNothing);
    });

    testWidgets('Chauffeur, Gains : les courses de test sont visibles, marquées, et ne comptent pas dans les gains', (tester) async {
      tester.view.physicalSize = const Size(430, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ConducteurGainsTab(
          service: _FinanceFactice([
            _ligne('r', 3000, date: DateTime.utc(2026, 11, 13, 9)),
            _ligne('t', 2000, test: true, date: DateTime.utc(2026, 11, 13, 11)),
          ]),
          chauffeurId: 'moussa',
          maintenant: _maintenant,
        ),
      ));
      await tester.pumpAndSettle();

      // « Sprint vous doit » : la part de la seule course réelle (90 % de 3 000).
      expect(find.text(formaterFcfa(2700)), findsWidgets);
      expect(find.text('1 course · 0 min en ligne'), findsNWidgets(2)); // jour et semaine : la course réelle
      // La note explique ce qui n'est pas compté.
      expect(find.byKey(const ValueKey('note-argent-de-test')), findsOneWidget);
      expect(find.textContaining('1 course en argent de test (${formaterFcfa(2000)})'), findsOneWidget);
      expect(find.textContaining('elles ne comptent pas dans vos gains'), findsOneWidget);
      // La course de test figure dans les dernières courses, marquée, sans part.
      expect(find.text('Payée par Wave · argent de test'), findsOneWidget);
      expect(find.textContaining('non compté'), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);
      expect(find.text('+${formaterFcfa(2700)}'), findsOneWidget); // la course réelle seule
      expect(tester.takeException(), isNull);
    });

    testWidgets('Chauffeur, Gains : sans argent de test, aucune note', (tester) async {
      tester.view.physicalSize = const Size(430, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ConducteurGainsTab(
          service: _FinanceFactice([_ligne('r', 3000, date: DateTime.utc(2026, 11, 13, 9))]),
          chauffeurId: 'moussa',
          maintenant: _maintenant,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-argent-de-test')), findsNothing);
      expect(find.textContaining('argent de test'), findsNothing);
    });

    testWidgets('Portefeuille : un mouvement en argent de test le dit, pas un mouvement en argent réel', (tester) async {
      final service = _PortefeuilleFactice(const [
        MouvementPortefeuille(id: 'a', type: MouvementPortefeuille.recharge, montantFcfa: 5000, soldeApresFcfa: 5000, argentDeTest: true),
        MouvementPortefeuille(id: 'b', type: MouvementPortefeuille.recharge, montantFcfa: 2000, soldeApresFcfa: 7000),
      ]);
      await tester.pumpWidget(MaterialApp(home: MouvementsPortefeuillePage(service: service, uid: 'awa')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('argent-de-test-a')), findsOneWidget);
      expect(find.text('Argent de test'), findsOneWidget);
      expect(find.byKey(const ValueKey('argent-de-test-b')), findsNothing);
    });
  });
}
