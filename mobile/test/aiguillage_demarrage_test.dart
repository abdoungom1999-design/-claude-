import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sprint/core/router/aiguillage_demarrage.dart';
import 'package:sprint/core/router/app_routes.dart';

/// Faux Firebase : le compte conservé, son rôle, et le temps que met la
/// session à être relue (asynchrone sur le web).
class _FauxFirebase {
  bool pret = true;
  String? uid;
  Completer<void>? lectureDeLaSession;
  Object? erreurSession;
  final roles = <String, String?>{};
  Object? erreurRole;
  Object? erreurPret;
  int lecturesSession = 0;
  int lecturesRole = 0;

  AiguillageDemarrage aiguillage() => AiguillageDemarrage(
        pret: () {
          if (erreurPret != null) throw erreurPret!;
          return pret;
        },
        attendreSession: () async {
          lecturesSession++;
          if (erreurSession != null) throw erreurSession!;
          await lectureDeLaSession?.future;
        },
        uidConnecte: () => uid,
        roleDe: (compte) async {
          lecturesRole++;
          if (erreurRole != null) throw erreurRole!;
          return roles[compte];
        },
      );
}

void main() {
  group('aiguillage de démarrage', () {
    test('sans Firebase (démo, test) : aucune redirection, réponse immédiate, aucune lecture', () {
      final faux = _FauxFirebase()
        ..pret = false
        ..uid = 'u1';
      final reponse = faux.aiguillage().destination(AppRoutes.welcome);
      expect(reponse, isNull);
      expect(reponse is Future, isFalse);
      expect(faux.lecturesSession + faux.lecturesRole, 0);
    });

    test('Firebase qui répond mal à « êtes-vous prêt » : on reste où l\'on est', () {
      final faux = _FauxFirebase()..erreurPret = StateError('pas d\'app');
      expect(faux.aiguillage().destination(AppRoutes.welcome), isNull);
    });

    test('personne de connecté : l\'écran de Bienvenue reste affiché', () async {
      final faux = _FauxFirebase();
      expect(await faux.aiguillage().destination(AppRoutes.welcome), isNull);
      expect(faux.lecturesRole, 0);
    });

    test('client connecté : directement son accueil', () async {
      final faux = _FauxFirebase()
        ..uid = 'u1'
        ..roles['u1'] = 'client';
      expect(await faux.aiguillage().destination(AppRoutes.welcome), AppRoutes.home);
    });

    test('chauffeur connecté : directement son espace', () async {
      final faux = _FauxFirebase()
        ..uid = 'u2'
        ..roles['u2'] = 'conducteur';
      expect(await faux.aiguillage().destination(AppRoutes.welcome), AppRoutes.conducteur);
    });

    test('administrateur connecté : directement son tableau de bord', () async {
      final faux = _FauxFirebase()
        ..uid = 'u3'
        ..roles['u3'] = 'admin';
      expect(await faux.aiguillage().destination(AppRoutes.welcome), AppRoutes.admin);
    });

    test('rôle introuvable, inconnu ou lecture en échec : l\'espace Client, jamais Bienvenue', () async {
      final sansRole = _FauxFirebase()..uid = 'u4';
      expect(await sansRole.aiguillage().destination(AppRoutes.welcome), AppRoutes.home);

      final inconnu = _FauxFirebase()
        ..uid = 'u5'
        ..roles['u5'] = 'quelqu\'un-d-autre';
      expect(await inconnu.aiguillage().destination(AppRoutes.welcome), AppRoutes.home);

      final enEchec = _FauxFirebase()
        ..uid = 'u6'
        ..erreurRole = Exception('réseau coupé');
      expect(await enEchec.aiguillage().destination(AppRoutes.welcome), AppRoutes.home);
    });

    test('attend la lecture de la session avant de décider (sur le web, elle est asynchrone)', () async {
      final faux = _FauxFirebase()..lectureDeLaSession = Completer<void>();
      final reponse = faux.aiguillage().destination(AppRoutes.welcome);
      expect(reponse, isA<Future<String?>>());

      var termine = false;
      unawaited((reponse as Future<String?>).whenComplete(() => termine = true));
      await pumpEventQueue();
      expect(termine, isFalse, reason: 'rien n\'est décidé tant que la session n\'est pas relue');

      // La session est relue : le compte apparaît, l'aiguillage le voit.
      faux
        ..uid = 'u1'
        ..roles['u1'] = 'client';
      faux.lectureDeLaSession!.complete();
      expect(await reponse, AppRoutes.home);
    });

    test('les autres adresses (liens directs, onglets) ne sont jamais redirigées, mais attendent la session', () async {
      final faux = _FauxFirebase()
        ..uid = 'u1'
        ..roles['u1'] = 'client'
        ..lectureDeLaSession = Completer<void>();
      final aiguillage = faux.aiguillage();
      final reponse = aiguillage.destination(AppRoutes.compteTab);
      expect(reponse, isA<Future<String?>>());
      faux.lectureDeLaSession!.complete();
      expect(await reponse, isNull);
      expect(faux.lecturesRole, 0);
    });

    test('la session n\'est lue qu\'une fois : ensuite les adresses ordinaires répondent tout de suite', () async {
      final faux = _FauxFirebase()
        ..uid = 'u1'
        ..roles['u1'] = 'client';
      final aiguillage = faux.aiguillage();
      await aiguillage.destination(AppRoutes.welcome);
      final suite = aiguillage.destination(AppRoutes.activiteTab);
      expect(suite, isNull);
      expect(suite is Future, isFalse);
      expect(faux.lecturesSession, 1);
    });

    test('plusieurs navigations avant la fin de la lecture ne la relancent pas', () async {
      final faux = _FauxFirebase()
        ..uid = 'u1'
        ..roles['u1'] = 'conducteur'
        ..lectureDeLaSession = Completer<void>();
      final aiguillage = faux.aiguillage();
      final a = aiguillage.destination(AppRoutes.welcome);
      final b = aiguillage.destination(AppRoutes.welcome);
      faux.lectureDeLaSession!.complete();
      expect(await a, AppRoutes.conducteur);
      expect(await b, AppRoutes.conducteur);
      expect(faux.lecturesSession, 1);
    });

    test('session illisible : on décide avec le compte que Firebase connaît, sinon Bienvenue', () async {
      final sansCompte = _FauxFirebase()..erreurSession = TimeoutException('trop long');
      expect(await sansCompte.aiguillage().destination(AppRoutes.welcome), isNull);

      final avecCompte = _FauxFirebase()
        ..erreurSession = TimeoutException('trop long')
        ..uid = 'u1'
        ..roles['u1'] = 'client';
      expect(await avecCompte.aiguillage().destination(AppRoutes.welcome), AppRoutes.home);
    });

    test('après « Se déconnecter » : retour à Bienvenue, sans rebond vers l\'accueil', () async {
      final faux = _FauxFirebase()
        ..uid = 'u1'
        ..roles['u1'] = 'client';
      final aiguillage = faux.aiguillage();
      expect(await aiguillage.destination(AppRoutes.welcome), AppRoutes.home);

      faux.uid = null; // la personne a appuyé sur « Se déconnecter »
      final reponse = aiguillage.destination(AppRoutes.welcome);
      expect(reponse, isNull);
      expect(reponse is Future, isFalse);
    });
  });

  group('avec le vrai routeur go_router', () {
    // Mêmes adresses que l'app ; chaque écran compte ses constructions.
    late _FauxFirebase faux;
    late int constructionsBienvenue;

    // Un seul aiguillage par routeur, comme dans l'app (il retient la session déjà lue).
    GoRouter routeur() {
      final aiguillage = faux.aiguillage();
      return GoRouter(
        initialLocation: AppRoutes.welcome,
        redirect: (context, state) => aiguillage.destination(state.matchedLocation),
        routes: [
          GoRoute(
            path: AppRoutes.welcome,
            builder: (_, __) {
              constructionsBienvenue++;
              return const Scaffold(body: Text('ÉCRAN BIENVENUE'));
            },
          ),
          GoRoute(path: AppRoutes.home, builder: (_, __) => const Scaffold(body: Text('ÉCRAN ACCUEIL CLIENT'))),
          GoRoute(path: AppRoutes.conducteur, builder: (_, __) => const Scaffold(body: Text('ÉCRAN ESPACE CHAUFFEUR'))),
          GoRoute(path: AppRoutes.admin, builder: (_, __) => const Scaffold(body: Text('ÉCRAN ADMIN'))),
        ],
      );
    }

    setUp(() {
      faux = _FauxFirebase();
      constructionsBienvenue = 0;
    });

    testWidgets('session conservée : l\'accueil s\'affiche directement, Bienvenue n\'est jamais construit',
        (tester) async {
      faux
        ..uid = 'u1'
        ..roles['u1'] = 'client'
        ..lectureDeLaSession = Completer<void>();
      await tester.pumpWidget(MaterialApp.router(routerConfig: routeur()));
      await tester.pump();

      // La session se relit encore : aucun écran, pas même Bienvenue.
      expect(find.text('ÉCRAN BIENVENUE'), findsNothing);
      expect(find.text('ÉCRAN ACCUEIL CLIENT'), findsNothing);

      faux.lectureDeLaSession!.complete();
      await tester.pumpAndSettle();
      expect(find.text('ÉCRAN ACCUEIL CLIENT'), findsOneWidget);
      expect(constructionsBienvenue, 0);
    });

    testWidgets('chauffeur : directement son espace, sans repasser par Bienvenue', (tester) async {
      faux
        ..uid = 'u2'
        ..roles['u2'] = 'conducteur';
      await tester.pumpWidget(MaterialApp.router(routerConfig: routeur()));
      await tester.pumpAndSettle();
      expect(find.text('ÉCRAN ESPACE CHAUFFEUR'), findsOneWidget);
      expect(constructionsBienvenue, 0);
    });

    testWidgets('administrateur : directement son tableau de bord', (tester) async {
      faux
        ..uid = 'u3'
        ..roles['u3'] = 'admin';
      await tester.pumpWidget(MaterialApp.router(routerConfig: routeur()));
      await tester.pumpAndSettle();
      expect(find.text('ÉCRAN ADMIN'), findsOneWidget);
      expect(constructionsBienvenue, 0);
    });

    testWidgets('personne de connecté : l\'écran de Bienvenue', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: routeur()));
      await tester.pumpAndSettle();
      expect(find.text('ÉCRAN BIENVENUE'), findsOneWidget);
      expect(find.text('ÉCRAN ACCUEIL CLIENT'), findsNothing);
    });

    testWidgets('« Se déconnecter » ramène à Bienvenue et la session n\'est pas rouverte toute seule', (tester) async {
      faux
        ..uid = 'u1'
        ..roles['u1'] = 'client';
      final routeurTest = routeur();
      await tester.pumpWidget(MaterialApp.router(routerConfig: routeurTest));
      await tester.pumpAndSettle();
      expect(find.text('ÉCRAN ACCUEIL CLIENT'), findsOneWidget);

      faux.uid = null; // appui sur « Se déconnecter »
      routeurTest.go(AppRoutes.welcome);
      await tester.pumpAndSettle();
      expect(find.text('ÉCRAN BIENVENUE'), findsOneWidget);
      expect(find.text('ÉCRAN ACCUEIL CLIENT'), findsNothing);
    });

    testWidgets('lien direct vers un onglet : affiché tel quel, après la lecture de la session', (tester) async {
      faux
        ..uid = 'u1'
        ..roles['u1'] = 'client';
      final aiguillage = faux.aiguillage();
      final routeurTest = GoRouter(
        initialLocation: AppRoutes.compteTab,
        redirect: (context, state) => aiguillage.destination(state.matchedLocation),
        routes: [
          GoRoute(path: AppRoutes.compteTab, builder: (_, __) => const Scaffold(body: Text('ÉCRAN COMPTE'))),
          GoRoute(path: AppRoutes.welcome, builder: (_, __) => const Scaffold(body: Text('ÉCRAN BIENVENUE'))),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: routeurTest));
      await tester.pumpAndSettle();
      expect(find.text('ÉCRAN COMPTE'), findsOneWidget);
    });
  });
}
