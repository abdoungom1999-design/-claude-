import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sprint/core/router/app_routes.dart';
import 'package:sprint/core/router/garde_session.dart';
import 'package:sprint/core/router/routage_sans_historique.dart';
import 'package:sprint/core/theme/app_theme.dart';
import 'package:sprint/core/widgets/racine_de_session.dart';

const _client = SessionOuverte('client');
const _chauffeur = SessionOuverte('conducteur');
const _admin = SessionOuverte('admin');
const _fermee = SessionFermee();

String? _vers(String chemin, EtatSession session, {bool actif = true}) =>
    GardeSession.destination(chemin: chemin, session: session, backendActif: actif);

void main() {
  group('Garde de session : connecté, jamais l\'écran de connexion', () {
    test('chaque espace revient à SA page racine, depuis tous les écrans de connexion', () {
      for (final page in GardeSession.pagesDeConnexion) {
        expect(_vers(page, _client), AppRoutes.home, reason: 'client depuis $page');
        expect(_vers(page, _chauffeur), AppRoutes.conducteur, reason: 'chauffeur depuis $page');
        expect(_vers(page, _admin), AppRoutes.admin, reason: 'admin depuis $page');
      }
    });

    test('toutes les pages de connexion sont couvertes', () {
      expect(GardeSession.pagesDeConnexion, {
        AppRoutes.welcome,
        AppRoutes.clientLogin,
        AppRoutes.clientRegister,
        AppRoutes.conducteurLogin,
        AppRoutes.conducteurRegister,
        AppRoutes.adminLogin,
        AppRoutes.espacePro,
      });
    });

    test('connecté, les pages de son espace ne bougent pas', () {
      for (final chemin in [
        AppRoutes.home,
        AppRoutes.activiteTab,
        AppRoutes.messagesTab,
        AppRoutes.compteTab,
        AppRoutes.clientPassager,
        AppRoutes.clientColis,
        AppRoutes.conducteur,
        AppRoutes.admin,
      ]) {
        expect(_vers(chemin, _client), isNull, reason: chemin);
      }
    });

    test('rôle illisible (réseau) : on ne déplace personne plutôt que de risquer le mauvais espace', () {
      expect(_vers(AppRoutes.welcome, const SessionOuverte(null)), isNull);
    });
  });

  group('Garde de session : déconnecté, pas d\'espace', () {
    test('les espaces renvoient à la bonne porte d\'entrée', () {
      expect(_vers(AppRoutes.home, _fermee), AppRoutes.welcome);
      expect(_vers(AppRoutes.activiteTab, _fermee), AppRoutes.welcome);
      expect(_vers(AppRoutes.messagesTab, _fermee), AppRoutes.welcome);
      expect(_vers(AppRoutes.compteTab, _fermee), AppRoutes.welcome);
      expect(_vers(AppRoutes.clientPassager, _fermee), AppRoutes.welcome);
      expect(_vers(AppRoutes.clientColis, _fermee), AppRoutes.welcome);
      expect(_vers(AppRoutes.conducteur, _fermee), AppRoutes.conducteurLogin);
      expect(_vers(AppRoutes.admin, _fermee), AppRoutes.adminLogin);
    });

    test('les écrans de connexion restent accessibles', () {
      for (final page in GardeSession.pagesDeConnexion) {
        expect(_vers(page, _fermee), isNull, reason: page);
      }
    });

    test('Firebase lent ou injoignable : personne n\'est mis dehors', () {
      expect(_vers(AppRoutes.home, const SessionInconnue()), isNull);
      expect(_vers(AppRoutes.welcome, const SessionInconnue()), isNull);
    });

    test('mode démo (sans projet Firebase) : aucune garde', () {
      expect(_vers(AppRoutes.home, _fermee, actif: false), isNull);
      expect(_vers(AppRoutes.welcome, _client, actif: false), isNull);
    });
  });

  group('Routeur : la connexion disparaît de la pile', () {
    Future<GoRouter> ouvrir(WidgetTester tester, EtatSession Function() session, {String depart = '/'}) async {
      final garde = GardeSession(lireSession: ({avecRole = false}) async => session(), backendActif: true);
      Widget page(String nom) => Scaffold(body: Text(nom));
      final routeur = GoRouter(
        initialLocation: depart,
        redirect: garde.rediriger,
        routes: [
          GoRoute(path: AppRoutes.welcome, builder: (_, __) => page('BIENVENUE')),
          GoRoute(path: AppRoutes.clientLogin, builder: (_, __) => page('CONNEXION')),
          GoRoute(path: AppRoutes.conducteurLogin, builder: (_, __) => page('CONNEXION PRO')),
          GoRoute(path: AppRoutes.adminLogin, builder: (_, __) => page('CONNEXION ADMIN')),
          GoRoute(path: AppRoutes.home, builder: (_, __) => page('ACCUEIL CLIENT')),
          GoRoute(path: AppRoutes.conducteur, builder: (_, __) => page('TABLEAU CHAUFFEUR')),
          GoRoute(path: AppRoutes.admin, builder: (_, __) => page('TABLEAU ADMIN')),
        ],
      );
      addTearDown(routeur.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: routeur));
      await tester.pumpAndSettle();
      return routeur;
    }

    testWidgets('connecté : ouvrir la connexion (retour arrière, lien) ramène à l\'accueil du bon espace', (tester) async {
      var session = _fermee as EtatSession;
      final routeur = await ouvrir(tester, () => session);
      expect(find.text('BIENVENUE'), findsOneWidget);

      session = _client;
      routeur.go(AppRoutes.clientLogin);
      await tester.pumpAndSettle();
      expect(find.text('ACCUEIL CLIENT'), findsOneWidget);

      session = _chauffeur;
      routeur.go(AppRoutes.conducteurLogin);
      await tester.pumpAndSettle();
      expect(find.text('TABLEAU CHAUFFEUR'), findsOneWidget);

      session = _admin;
      routeur.go(AppRoutes.adminLogin);
      await tester.pumpAndSettle();
      expect(find.text('TABLEAU ADMIN'), findsOneWidget);
    });

    testWidgets('démarrage à froid connecté sur l\'écran de bienvenue : directement l\'accueil', (tester) async {
      await ouvrir(tester, () => _client);
      expect(find.text('ACCUEIL CLIENT'), findsOneWidget);
      expect(find.text('BIENVENUE'), findsNothing);
    });

    testWidgets('après connexion (go vers l\'accueil), plus rien derrière : la connexion est détruite', (tester) async {
      var session = _fermee as EtatSession;
      final routeur = await ouvrir(tester, () => session);
      routeur.push(AppRoutes.clientLogin);
      await tester.pumpAndSettle();
      expect(find.text('CONNEXION'), findsOneWidget);
      expect(routeur.canPop(), isTrue);

      session = _client;
      routeur.go(AppRoutes.home);
      await tester.pumpAndSettle();
      expect(find.text('ACCUEIL CLIENT'), findsOneWidget);
      expect(routeur.canPop(), isFalse, reason: 'aucune page de connexion ne reste dans la pile');
    });

    testWidgets('déconnecté : l\'espace demandé renvoie à la bonne connexion', (tester) async {
      final routeur = await ouvrir(tester, () => _fermee);
      routeur.go(AppRoutes.conducteur);
      await tester.pumpAndSettle();
      expect(find.text('CONNEXION PRO'), findsOneWidget);
      routeur.go(AppRoutes.admin);
      await tester.pumpAndSettle();
      expect(find.text('CONNEXION ADMIN'), findsOneWidget);
      routeur.go(AppRoutes.home);
      await tester.pumpAndSettle();
      expect(find.text('BIENVENUE'), findsOneWidget);
    });
  });

  group('Racine de session : le retour ne quitte jamais la racine', () {
    Future<void> retour(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    testWidgets('sur le site : sous-pages fermées une à une, puis la racine tient bon', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: RacineDeSession(
          actif: true,
          child: Builder(
            builder: (context) => Scaffold(
              body: Column(children: [
                const Text('RACINE'),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (context) => Scaffold(
                      appBar: AppBar(title: const Text('SOUS-PAGE A')),
                      body: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: const Text('SOUS-PAGE B')))),
                        ),
                        child: const Text('ouvrir B'),
                      ),
                    ),
                  )),
                  child: const Text('ouvrir A'),
                ),
              ]),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ouvrir B'));
      await tester.pumpAndSettle();
      expect(find.text('SOUS-PAGE B'), findsOneWidget);

      await retour(tester);
      expect(find.text('SOUS-PAGE A'), findsOneWidget);
      await retour(tester);
      expect(find.text('RACINE'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await retour(tester);
        expect(find.text('RACINE'), findsOneWidget, reason: 'retour n°${i + 1} depuis la racine');
      }
    });

    testWidgets('depuis un autre onglet, le retour revient d\'abord à l\'onglet principal', (tester) async {
      var onglet = 1;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => RacineDeSession(
            actif: true,
            surRetour: () {
              if (onglet == 0) return false;
              setState(() => onglet = 0);
              return true;
            },
            child: Scaffold(body: Text('ONGLET $onglet')),
          ),
        ),
      ));
      expect(find.text('ONGLET 1'), findsOneWidget);
      await retour(tester);
      expect(find.text('ONGLET 0'), findsOneWidget);
      await retour(tester);
      expect(find.text('ONGLET 0'), findsOneWidget);
    });

    testWidgets('hors site (APK Android) : comportement du système conservé', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const RacineDeSession(actif: false, child: Scaffold(body: Text('ACCUEIL'))),
              )),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('ACCUEIL'), findsOneWidget);
      await retour(tester);
      expect(find.text('ACCUEIL'), findsNothing);
    });
  });

  group('Historique du navigateur', () {
    test('le fournisseur n\'écrit jamais dans l\'historique et relaie le reste', () {
      final interne = _Fournisseur();
      final fournisseur = RouteSansHistorique(interne);
      var appels = 0;
      void ecouteur() => appels++;
      fournisseur.addListener(ecouteur);
      interne.notifier();
      expect(appels, 1);
      expect(fournisseur.value.uri.path, '/accueil');

      fournisseur.routerReportsNewRouteInformation(RouteInformation(uri: Uri.parse('/client/login')));
      fournisseur.routerReportsNewRouteInformation(
        RouteInformation(uri: Uri.parse('/accueil')),
        type: RouteInformationReportingType.navigate,
      );
      expect(interne.rapports, 0, reason: 'aucune entrée d\'historique ajoutée au navigateur');

      fournisseur.removeListener(ecouteur);
      interne.notifier();
      expect(appels, 1);
    });
  });

  group('Flèche « Retour » sur les sous-pages', () {
    testWidgets('même flèche visible partout (thème), et elle ferme la page', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Sous-page')))),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Sous-page'), findsNothing);
    });

    test('toutes les sous-pages des trois espaces ont une en-tête avec retour', () {
      // Sous-pages ouvertes par Navigator.push / context.push : un AppBar
      // (flèche automatique) ou l'AuthScaffold (flèche intégrée).
      const sousPages = [
        // Client
        'lib/features/client/presentation/passager_page.dart',
        'lib/features/client/presentation/colis_page.dart',
        'lib/features/client/presentation/suivi_course_page.dart',
        'lib/features/activite/presentation/detail_course_page.dart',
        'lib/features/activite/presentation/receipts_page.dart',
        'lib/features/support/presentation/signalement_page.dart',
        'lib/features/messages/presentation/messagerie_chat_page.dart',
        'lib/features/messages/presentation/chat_page.dart',
        'lib/features/compte/presentation/a_propos_page.dart',
        'lib/features/compte/presentation/aide_support_page.dart',
        'lib/features/compte/presentation/centre_aide_page.dart',
        'lib/features/compte/presentation/courses_a_noter_page.dart',
        'lib/features/compte/presentation/favoris_page.dart',
        'lib/features/compte/presentation/informations_personnelles_page.dart',
        'lib/features/compte/presentation/inviter_amis_page.dart',
        'lib/features/compte/presentation/mes_notifications_page.dart',
        'lib/features/compte/presentation/notifications_page.dart',
        'lib/features/compte/presentation/nous_contacter_page.dart',
        'lib/features/compte/presentation/parametres_page.dart',
        'lib/features/compte/presentation/preferences_page.dart',
        'lib/features/compte/presentation/securite_page.dart',
        'lib/core/widgets/legal_page.dart',
        // Chauffeur
        'lib/features/auth/presentation/conducteur_onboarding/conducteur_onboarding_page.dart',
        'lib/features/onboarding/presentation/espace_pro_page.dart',
        // Admin
        'lib/features/admin/presentation/admin_ticket_page.dart',
        // Connexions et inscription (retour intégré à l'AuthScaffold)
        'lib/features/auth/presentation/client_login_page.dart',
        'lib/features/auth/presentation/register_page.dart',
        'lib/features/auth/presentation/conducteur_login_page.dart',
        'lib/features/auth/presentation/admin_login_page.dart',
      ];
      for (final fichier in sousPages) {
        final source = File(fichier).readAsStringSync();
        final aEnTete = source.contains('AppBar(') || source.contains('AuthScaffold(');
        expect(aEnTete, isTrue, reason: '$fichier : ni AppBar ni AuthScaffold, donc pas de flèche retour');
        expect(
          source.contains('automaticallyImplyLeading: false'),
          isFalse,
          reason: '$fichier : la flèche retour automatique est désactivée',
        );
      }
    });

    test('le sas de paiement a sa flèche (elle fait comme « Annuler »)', () {
      final source = File('lib/features/client/presentation/payment_processing_page.dart').readAsStringSync();
      expect(source.contains('Icons.arrow_back_rounded'), isTrue);
    });
  });
}

class _Fournisseur extends RouteInformationProvider with ChangeNotifier {
  var rapports = 0;

  void notifier() => notifyListeners();

  @override
  RouteInformation get value => RouteInformation(uri: Uri.parse('/accueil'));

  @override
  void routerReportsNewRouteInformation(RouteInformation routeInformation,
      {RouteInformationReportingType type = RouteInformationReportingType.none}) {
    rapports++;
  }
}
