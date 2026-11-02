import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sprint/core/network/api_exception.dart';
import 'package:sprint/core/router/app_router.dart';
import 'package:sprint/core/router/app_routes.dart';
import 'package:sprint/core/theme/app_theme.dart';
import 'package:sprint/features/auth/data/auth_repository.dart';
import 'package:sprint/features/auth/presentation/conducteur_login_page.dart';

/// Capture du client (iPhone, app web installée, 2 novembre 2026) : en
/// glissant pour revenir en arrière depuis « Compte », iOS affichait l'image
/// qu'il avait gardée de l'écran de connexion (bouton encore en chargement),
/// à côté de « Compte » ; puis le chauffeur connecté était renvoyé à son
/// accueil, qui reprenait une entrée d'historique : le glissement suivant
/// retombait sur la même image. Sur iPhone, les écrans ne s'empilent plus
/// dans l'historique du navigateur : rien derrière l'accueil, aucune image
/// figée, aucun rebond.

/// Ce que l'app signale au navigateur à chaque changement d'écran.
List<Map<Object?, Object?>> _ecouterHistorique(WidgetTester tester) {
  final rapports = <Map<Object?, Object?>>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (appel) async {
    if (appel.method == 'routeInformationUpdated') rapports.add(appel.arguments as Map<Object?, Object?>);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, null));
  return rapports;
}

GoRouter _routeur({required bool iPhoneWeb, AuthRepository? connexion}) => GoRouter(
      initialLocation: AppRoutes.espacePro,
      routerNeglect: historiqueNavigateurNeutralise(
        web: true,
        plateforme: iPhoneWeb ? TargetPlatform.iOS : TargetPlatform.android,
      ),
      routes: [
        GoRoute(
          path: AppRoutes.espacePro,
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(onPressed: () => context.push(AppRoutes.conducteurLogin), child: const Text('ESPACE PRO')),
            ),
          ),
        ),
        GoRoute(path: AppRoutes.conducteurLogin, builder: (_, __) => ConducteurLoginPage(authRepository: connexion)),
        GoRoute(path: AppRoutes.conducteur, builder: (_, __) => const Scaffold(body: Center(child: Text('COMPTE')))),
      ],
    );

/// Connexion qui attend qu'on la laisse aboutir (comme sur un réseau lent).
class _ConnexionEnAttente extends AuthRepository {
  final reponse = Completer<void>();

  @override
  Future<void> connecterConducteur({required String identifiant, required String motDePasse}) => reponse.future;
}

Future<void> _seConnecter(WidgetTester tester) async {
  final champs = find.byType(TextFormField);
  await tester.enterText(champs.at(0), 'moussa@test.sn');
  await tester.enterText(champs.at(1), 'motdepasse1');
  await tester.tap(find.text('Se connecter'));
  await tester.pump();
}

void main() {
  test('historique du navigateur neutralisé sur iPhone (site et app web installée) seulement', () {
    expect(historiqueNavigateurNeutralise(web: true, plateforme: TargetPlatform.iOS), isTrue);
    for (final plateforme in [TargetPlatform.android, TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux]) {
      expect(historiqueNavigateurNeutralise(web: true, plateforme: plateforme), isFalse, reason: plateforme.name);
    }
    // L'APK (et toute app installée hors navigateur) n'a pas d'historique de navigateur.
    expect(historiqueNavigateurNeutralise(web: false, plateforme: TargetPlatform.iOS), isFalse);
  });

  test('le routeur de l\'app applique ce réglage', () {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();
    expect(
      source,
      contains('routerNeglect: historiqueNavigateurNeutralise(web: kIsWeb, plateforme: defaultTargetPlatform)'),
    );
  });

  testWidgets('iPhone : Espace Pro › connexion › accueil sans aucune entrée d\'historique ajoutée (rien à revoir en glissant)',
      (tester) async {
    final rapports = _ecouterHistorique(tester);
    final connexion = _ConnexionEnAttente();
    await tester.pumpWidget(MaterialApp.router(routerConfig: _routeur(iPhoneWeb: true, connexion: connexion), theme: AppTheme.sombre));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ESPACE PRO'));
    await tester.pumpAndSettle();
    await _seConnecter(tester);
    connexion.reponse.complete();
    await tester.pumpAndSettle();
    expect(find.text('COMPTE'), findsOneWidget);
    expect(rapports, isNotEmpty);
    expect(rapports.every((r) => r['replace'] == true), isTrue, reason: '$rapports');
    expect(rapports.last['uri'], AppRoutes.conducteur, reason: 'l\'adresse reste à jour');
  });

  testWidgets('ailleurs (Android, ordinateur) : l\'historique du navigateur est gardé, le bouton retour aussi', (tester) async {
    final rapports = _ecouterHistorique(tester);
    final routeur = _routeur(iPhoneWeb: false);
    await tester.pumpWidget(MaterialApp.router(routerConfig: routeur, theme: AppTheme.sombre));
    await tester.pumpAndSettle();
    routeur.go(AppRoutes.conducteur);
    await tester.pumpAndSettle();
    expect(rapports.any((r) => r['replace'] == false), isTrue, reason: '$rapports');
  });

  testWidgets('connexion en cours : ni retour ni glissement de retour ; puis l\'accueil arrive net', (tester) async {
    final connexion = _ConnexionEnAttente();
    await tester.pumpWidget(MaterialApp.router(routerConfig: _routeur(iPhoneWeb: true, connexion: connexion), theme: AppTheme.sombre));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ESPACE PRO'));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.text('Espace Conducteur')))!;
    expect(route.popGestureEnabled, isTrue, reason: 'avant la connexion, le glissement de retour marche');

    await _seConnecter(tester);
    expect(route.popGestureEnabled, isFalse, reason: 'pas de glissement pendant la connexion');
    await tester.binding.handlePopRoute(); // bouton retour
    await tester.pump(const Duration(milliseconds: 600)); // (l'indicateur de chargement tourne sans fin)
    expect(find.text('Espace Conducteur'), findsOneWidget);
    expect(find.text('ESPACE PRO'), findsNothing);

    connexion.reponse.complete();
    await tester.pumpAndSettle();
    expect(find.text('COMPTE'), findsOneWidget);
    expect(find.text('Espace Conducteur'), findsNothing);
  });

  testWidgets('connexion refusée : l\'écran redevient normal, le retour aussi', (tester) async {
    final connexion = _ConnexionEnAttente();
    await tester.pumpWidget(MaterialApp.router(routerConfig: _routeur(iPhoneWeb: true, connexion: connexion), theme: AppTheme.sombre));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ESPACE PRO'));
    await tester.pumpAndSettle();
    await _seConnecter(tester);
    connexion.reponse.completeError(ApiException('Numéro ou mot de passe incorrect.'));
    await tester.pumpAndSettle();
    expect(find.text('Numéro ou mot de passe incorrect.'), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.text('Espace Conducteur')))!;
    expect(route.popGestureEnabled, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('ESPACE PRO'), findsOneWidget);
  });
}
