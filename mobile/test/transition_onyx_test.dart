import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sprint/core/router/app_router.dart';
import 'package:sprint/core/router/app_routes.dart';
import 'package:sprint/core/router/transition_onyx.dart';
import 'package:sprint/core/theme/app_colors.dart';

/// Bug signalé par le client (2 novembre 2026) : l'écran de connexion
/// « Espace Conducteur » se superposait parfois à la carte de l'accueil
/// chauffeur. L'accueil arrive désormais sur un fond Onyx opaque : l'écran
/// précédent n'est jamais visible par-dessus la carte.
void main() {
  GoRoute route(String chemin) =>
      appRouter.configuration.routes.whereType<GoRoute>().firstWhere((r) => r.path == chemin);

  test('dans l\'app : l\'accueil chauffeur utilise ce fondu, la connexion renvoie un chauffeur connecté à son accueil', () {
    final accueil = route(AppRoutes.conducteur);
    expect(accueil.pageBuilder, isNotNull);
    expect(accueil.builder, isNull);
    final connexion = route(AppRoutes.conducteurLogin);
    expect(connexion.redirect, isNotNull);
    expect(connexion.builder, isNotNull);
  });

  testWidgets('pendant toute la transition, un fond Onyx opaque couvre l\'écran précédent', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final routeur = GoRouter(
      initialLocation: '/connexion',
      routes: [
        GoRoute(path: '/connexion', builder: (_, __) => const Scaffold(body: Center(child: Text('CONNEXION')))),
        GoRoute(
          path: '/accueil',
          pageBuilder: (_, state) => transitionOnyx(
            state,
            // Comme la carte en cours de chargement : un fond transparent.
            const Scaffold(backgroundColor: Colors.transparent, body: Center(child: Text('CARTE'))),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: routeur,
      theme: ThemeData(platform: TargetPlatform.android),
    ));
    await tester.pumpAndSettle();

    routeur.go('/accueil');
    await tester.pump(); // la navigation est traitée
    await tester.pump(); // première image de la transition
    // L'écran de connexion est encore là, dessous, le temps de la transition…
    expect(find.text('CONNEXION'), findsOneWidget);
    for (final instant in [0, 40, 120, 200]) {
      if (instant > 0) await tester.pump(const Duration(milliseconds: 40));
      final fond = find.ancestor(
        of: find.text('CARTE'),
        matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == AppColors.fond),
      );
      expect(fond, findsOneWidget, reason: 'à $instant ms');
      expect(tester.widget<ColoredBox>(fond).color.a, 1.0);
      // … mais entièrement caché par le fond Onyx, qui couvre tout l'écran.
      expect(tester.getRect(fond), Offset.zero & const Size(400, 800), reason: 'tout l\'écran, à $instant ms');
    }
    final fondu = tester.widget<FadeTransition>(
      find.ancestor(of: find.text('CARTE'), matching: find.byType(FadeTransition)).first,
    );
    expect(fondu.opacity.value, lessThan(1.0));

    await tester.pumpAndSettle();
    expect(find.text('CONNEXION'), findsNothing);
    expect(find.text('CARTE'), findsOneWidget);
  });
}
