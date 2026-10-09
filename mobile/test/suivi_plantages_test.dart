import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/suivi/suivi_plantages.dart';
import 'package:sprint/features/admin/presentation/sections/admin_parametres_section.dart';
import 'package:sprint/features/admin/presentation/widgets/carte_suivi_plantages.dart';

class _JournalFactice implements JournalPlantages {
  final collectes = <bool>[];
  final erreursFramework = <FlutterErrorDetails>[];
  final erreursNonRattrapees = <(Object, StackTrace)>[];
  var plantagesDeTest = 0;

  /// Fait échouer le journal (Crashlytics indisponible, plugin absent…).
  bool enPanne = false;

  @override
  Future<void> activerLaCollecte(bool activee) async {
    if (enPanne) throw StateError('Crashlytics indisponible');
    collectes.add(activee);
  }

  @override
  void erreurDuFramework(FlutterErrorDetails details) {
    if (enPanne) throw StateError('Crashlytics indisponible');
    erreursFramework.add(details);
  }

  @override
  void erreurNonRattrapee(Object erreur, StackTrace pile) {
    if (enPanne) throw StateError('Crashlytics indisponible');
    erreursNonRattrapees.add((erreur, pile));
  }

  @override
  void plantagePourTest() => plantagesDeTest++;
}

/// Les gestionnaires d'erreurs sont globaux : on les remet comme on les a trouvés.
void _restaurerLesGestionnaires() {
  final erreurFlutter = FlutterError.onError;
  final erreurAsynchrone = PlatformDispatcher.instance.onError;
  addTearDown(() {
    FlutterError.onError = erreurFlutter;
    PlatformDispatcher.instance.onError = erreurAsynchrone;
  });
}

void main() {
  group('branchement', () {
    test('appareil non compatible (web, iPhone, ordinateur) : rien n\'est branché, rien n\'est touché', () async {
      _restaurerLesGestionnaires();
      final avant = FlutterError.onError;
      final journal = _JournalFactice();
      final suivi = SuiviDesPlantages(journal: journal, compatible: false, versionFinale: true);

      await suivi.brancher();

      expect(suivi.actif, isFalse);
      expect(suivi.testable, isFalse);
      expect(journal.collectes, isEmpty);
      expect(FlutterError.onError, same(avant));
      suivi.plantagePourTest();
      expect(journal.plantagesDeTest, 0);
    });

    test('Android en version finale : la collecte est activée et les erreurs partent vers Crashlytics', () async {
      _restaurerLesGestionnaires();
      final journal = _JournalFactice();
      final suivi = SuiviDesPlantages(journal: journal, compatible: true, versionFinale: true);

      await suivi.brancher();

      expect(suivi.actif, isTrue);
      expect(journal.collectes, [true]);

      final details = FlutterErrorDetails(exception: StateError('écran cassé'), stack: StackTrace.current);
      FlutterError.onError!(details);
      expect(journal.erreursFramework, [details]);

      final pile = StackTrace.current;
      final rattrape = PlatformDispatcher.instance.onError!(StateError('erreur asynchrone'), pile);
      expect(rattrape, isTrue, reason: 'l\'erreur est prise en charge : elle ne doit pas être relancée');
      expect(journal.erreursNonRattrapees.single.$1, isA<StateError>());
      expect(journal.erreursNonRattrapees.single.$2, same(pile));
    });

    test('l\'affichage habituel des erreurs est conservé (le gestionnaire précédent est toujours appelé)', () async {
      _restaurerLesGestionnaires();
      final vues = <FlutterErrorDetails>[];
      FlutterError.onError = vues.add;
      final journal = _JournalFactice();
      final suivi = SuiviDesPlantages(journal: journal, compatible: true, versionFinale: true);

      await suivi.brancher();
      final details = FlutterErrorDetails(exception: StateError('x'));
      FlutterError.onError!(details);

      expect(vues, [details]);
      expect(journal.erreursFramework, [details]);
    });

    test('en développement ou en test (pas une version finale) : suivi branché mais collecte coupée, test impossible',
        () async {
      _restaurerLesGestionnaires();
      final journal = _JournalFactice();
      final suivi = SuiviDesPlantages(journal: journal, compatible: true, versionFinale: false);

      await suivi.brancher();

      expect(suivi.actif, isTrue);
      expect(journal.collectes, [false]);
      expect(suivi.testable, isFalse);
      suivi.plantagePourTest();
      expect(journal.plantagesDeTest, 0);
    });

    test('un second appel ne rebranche pas (pas de rapport en double)', () async {
      _restaurerLesGestionnaires();
      final journal = _JournalFactice();
      final suivi = SuiviDesPlantages(journal: journal, compatible: true, versionFinale: true);

      await suivi.brancher();
      final apres = FlutterError.onError;
      await suivi.brancher();

      expect(FlutterError.onError, same(apres));
      expect(journal.collectes, [true]);
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('une fois')));
      expect(journal.erreursFramework, hasLength(1));
    });

    test('Crashlytics en panne au démarrage : l\'app démarre quand même, sans rien brancher', () async {
      _restaurerLesGestionnaires();
      final avant = FlutterError.onError;
      final journal = _JournalFactice()..enPanne = true;
      final suivi = SuiviDesPlantages(journal: journal, compatible: true, versionFinale: true);

      await suivi.brancher(); // ne doit pas lever

      expect(suivi.actif, isFalse);
      expect(FlutterError.onError, same(avant));
    });

    test('Crashlytics en panne plus tard : l\'erreur d\'origine passe, le suivi ne lève rien', () async {
      _restaurerLesGestionnaires();
      final journal = _JournalFactice();
      final suivi = SuiviDesPlantages(journal: journal, compatible: true, versionFinale: true);
      await suivi.brancher();
      journal.enPanne = true;

      FlutterError.onError!(FlutterErrorDetails(exception: StateError('x'))); // ne doit pas lever
      expect(PlatformDispatcher.instance.onError!(StateError('y'), StackTrace.current), isTrue);
    });

    test('le plantage de test n\'a lieu que sur une app finale branchée', () async {
      _restaurerLesGestionnaires();
      final journal = _JournalFactice();
      final suivi = SuiviDesPlantages(journal: journal, compatible: true, versionFinale: true);

      suivi.plantagePourTest();
      expect(journal.plantagesDeTest, 0, reason: 'pas encore branché');

      await suivi.brancher();
      expect(suivi.testable, isTrue);
      suivi.plantagePourTest();
      expect(journal.plantagesDeTest, 1);
    });
  });

  group('carte Admin « Suivi des plantages »', () {
    Future<void> afficher(WidgetTester tester, Widget carte) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: carte))));
      await tester.pumpAndSettle();
    }

    Future<SuiviDesPlantages> suiviPret(_JournalFactice journal, {bool compatible = true, bool finale = true}) async {
      _restaurerLesGestionnaires();
      final suivi = SuiviDesPlantages(journal: journal, compatible: compatible, versionFinale: finale);
      await suivi.brancher();
      return suivi;
    }

    testWidgets('absente quand le suivi ne peut pas envoyer de rapport (web, iPhone, développement)', (tester) async {
      for (final (compatible, finale) in [(false, true), (true, false)]) {
        final suivi = await suiviPret(_JournalFactice(), compatible: compatible, finale: finale);
        await afficher(tester, CarteSuiviPlantages(suivi: suivi));
        expect(find.text('Suivi des plantages'), findsNothing, reason: 'compatible=$compatible finale=$finale');
        expect(find.text('Tester le suivi'), findsNothing);
      }
    });

    testWidgets('présente sur Android en version finale, avec ce qui est envoyé et ce qui n\'est pas couvert',
        (tester) async {
      final suivi = await suiviPret(_JournalFactice());
      await afficher(tester, CarteSuiviPlantages(suivi: suivi));

      expect(find.text('Suivi des plantages'), findsOneWidget);
      expect(find.textContaining('Firebase Crashlytics'), findsOneWidget);
      expect(find.textContaining('aucun nom, numéro ni identifiant de compte'), findsOneWidget);
      expect(find.textContaining('iPhone'), findsOneWidget);
      expect(find.text('Tester le suivi'), findsOneWidget);
    });

    testWidgets('« Tester le suivi » demande confirmation ; annuler ne plante rien', (tester) async {
      final journal = _JournalFactice();
      final suivi = await suiviPret(journal);
      await afficher(tester, CarteSuiviPlantages(suivi: suivi));

      await tester.tap(find.text('Tester le suivi'));
      await tester.pumpAndSettle();
      expect(find.text('Planter l\'application ?'), findsOneWidget);
      expect(journal.plantagesDeTest, 0, reason: 'rien ne plante avant la confirmation');

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.text('Planter l\'application ?'), findsNothing);
      expect(journal.plantagesDeTest, 0);
    });

    testWidgets('confirmer plante l\'application une seule fois', (tester) async {
      final journal = _JournalFactice();
      final suivi = await suiviPret(journal);
      await afficher(tester, CarteSuiviPlantages(suivi: suivi));

      await tester.tap(find.text('Tester le suivi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Planter pour tester'));
      await tester.pumpAndSettle();

      expect(journal.plantagesDeTest, 1);
    });

    testWidgets(
        'dans Admin > Paramètres (version réelle) : la carte apparaît après le stockage KYC, seulement si le suivi est actif',
        (tester) async {
      final actif = await suiviPret(_JournalFactice());
      await afficher(tester, AdminParametresSection(demo: false, suivi: actif));
      expect(find.text('Règles en vigueur'), findsOneWidget);
      expect(find.text('Suivi des plantages'), findsOneWidget);
      final kyc = tester.getTopLeft(find.text('Stockage des documents KYC')).dy;
      final suivi = tester.getTopLeft(find.text('Suivi des plantages')).dy;
      expect(suivi, greaterThan(kyc));

      final inactif = await suiviPret(_JournalFactice(), compatible: false);
      await afficher(tester, AdminParametresSection(demo: false, suivi: inactif));
      expect(find.text('Règles en vigueur'), findsOneWidget);
      expect(find.text('Suivi des plantages'), findsNothing);
    });

    testWidgets('par défaut (tests, ordinateur) : le suivi de l\'app n\'est pas actif, la carte reste cachée',
        (tester) async {
      await afficher(tester, const AdminParametresSection(demo: false));
      expect(find.text('Suivi des plantages'), findsNothing);
      expect(SuiviDesPlantages.instance.testable, isFalse);
    });
  });
}
