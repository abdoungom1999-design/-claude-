import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sprint/core/router/app_router.dart';
import 'package:sprint/core/router/app_routes.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/core/theme/app_theme.dart';
import 'package:sprint/core/theme/transition_ecrans.dart';

/// Bug signalé par le client (2 novembre 2026, après la publication 118) :
/// l'écran de connexion « Espace Conducteur » (bouton en chargement) se
/// superposait à l'écran « Compte » et se figeait à mi-chemin. Cause : la
/// transition Android par défaut de Flutter (fondu enchaîné, deux écrans
/// semi-transparents à la fois, l'ancien gardé dessous jusqu'à la fin) et le
/// retour prédictif d'Android 16 (l'écran suit le doigt, et reste figé si une
/// navigation a lieu pendant le geste). Désormais, un seul glissement opaque
/// pour toute l'app : un écran chasse l'autre.
const _taille = Size(400, 800);

void _ecran(WidgetTester tester) {
  tester.view.physicalSize = _taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _page(String nom) => find.byKey(ValueKey(nom));

/// Opacité réelle d'un écran : produit des fondus qui l'englobent.
double _opacite(WidgetTester tester, String nom) {
  var opacite = 1.0;
  final fondus = find.ancestor(of: _page(nom), matching: find.byWidgetPredicate((w) => w is FadeTransition || w is Opacity));
  for (final element in fondus.evaluate()) {
    final w = element.widget;
    opacite *= w is FadeTransition ? w.opacity.value : (w as Opacity).opacity;
  }
  return opacite;
}

/// Mêmes adresses que l'app : Espace Pro › Espace Conducteur › accueil (Compte).
GoRouter _routeur({String depart = '/espace-pro'}) {
  Widget ecran(String nom, VoidCallback Function(BuildContext) action, {Color? fond}) => Builder(
        builder: (context) => Scaffold(
          key: ValueKey(nom),
          backgroundColor: fond,
          body: Center(child: TextButton(onPressed: action(context), child: Text(nom))),
        ),
      );
  return GoRouter(
    initialLocation: depart,
    routes: [
      GoRoute(path: '/espace-pro', builder: (_, __) => ecran('ESPACE PRO', (c) => () => c.push('/conducteur/connexion'))),
      // Fond transparent : même ainsi, rien ne doit se voir à travers.
      GoRoute(
        path: '/conducteur/connexion',
        builder: (_, __) => ecran('CONNEXION', (c) => () => c.go('/conducteur'), fond: Colors.transparent),
      ),
      GoRoute(path: '/conducteur', builder: (_, __) => ecran('COMPTE', (c) => () => c.go('/espace-pro'))),
    ],
  );
}

Future<GoRouter> _ouvrir(WidgetTester tester, {String depart = '/espace-pro', bool mouvementReduit = false}) async {
  _ecran(tester);
  final routeur = _routeur(depart: depart);
  await tester.pumpWidget(MaterialApp.router(
    routerConfig: routeur,
    theme: AppTheme.sombre,
    builder: mouvementReduit
        ? (context, page) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: page!)
        : null,
  ));
  await tester.pumpAndSettle();
  return routeur;
}

/// Suit la transition image par image : chaque écran visible reste opaque, et
/// celui qui arrive [devant] couvre toute la partie droite de celui qui est
/// [derriere] (aucun vide, aucune transparence). Rend les bords gauches de
/// l'écran qui arrive.
Future<List<double>> _suivre(WidgetTester tester, {required String devant, required String derriere}) async {
  final bords = <double>[];
  for (var i = 0; i < 6; i++) {
    for (final nom in [devant, derriere]) {
      if (_page(nom).evaluate().isNotEmpty) expect(_opacite(tester, nom), 1.0, reason: '$nom, image $i');
    }
    final avant = tester.getRect(_page(devant));
    expect(avant.size, _taille, reason: 'écran entier, image $i');
    if (_page(derriere).evaluate().isNotEmpty) {
      expect(avant.left, lessThanOrEqualTo(tester.getRect(_page(derriere)).right), reason: 'aucun vide, image $i');
    }
    bords.add(avant.left);
    await tester.pump(const Duration(milliseconds: 50));
  }
  return bords;
}

Future<void> _geste(WidgetTester tester, String methode, [double? progression]) async {
  final appel = MethodCall(
    methode,
    progression == null ? null : {'touchOffset': [5.0, 300.0], 'progress': progression, 'swipeEdge': 0},
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(appel),
    (_) {},
  );
  await tester.pump();
}

void main() {
  test('thème : glissement opaque sur Android (et ordinateur) ; iPhone et Mac gardent leur glissement natif, sur fond opaque', () {
    final builders = AppTheme.sombre.pageTransitionsTheme.builders;
    for (final plateforme in [TargetPlatform.android, TargetPlatform.fuchsia, TargetPlatform.windows, TargetPlatform.linux]) {
      expect(builders[plateforme], isA<GlissementOnyxPageTransitionsBuilder>(), reason: plateforme.name);
    }
    expect(builders[TargetPlatform.iOS], isA<GlissementNatifOnyxPageTransitionsBuilder>());
    expect(builders[TargetPlatform.macOS], isA<GlissementNatifOnyxPageTransitionsBuilder>());
    // Le glissement natif d'iOS est conservé tel quel (durée, geste de retour).
    expect(builders[TargetPlatform.iOS]!.transitionDuration, const CupertinoPageTransitionsBuilder().transitionDuration);
  });

  test('dans l\'app : l\'accueil chauffeur suit la transition commune ; un chauffeur connecté qui revient sur la connexion retrouve son accueil', () {
    GoRoute route(String chemin) => appRouter.configuration.routes.whereType<GoRoute>().firstWhere((r) => r.path == chemin);
    final accueil = route(AppRoutes.conducteur);
    expect(accueil.builder, isNotNull);
    expect(accueil.pageBuilder, isNull);
    expect(route(AppRoutes.conducteurLogin).redirect, isNotNull);
  });

  testWidgets('Espace Pro › Espace Conducteur : l\'écran de connexion, opaque, chasse l\'autre', (tester) async {
    await _ouvrir(tester);
    await tester.tap(find.text('ESPACE PRO'));
    await tester.pump(); // la navigation est traitée
    await tester.pump(); // première image
    final bords = await _suivre(tester, devant: 'CONNEXION', derriere: 'ESPACE PRO');
    expect(bords.first, greaterThan(0));
    for (var i = 1; i < bords.length; i++) {
      expect(bords[i], lessThanOrEqualTo(bords[i - 1]));
    }
    // Fond Onyx opaque sous l'écran, même au fond transparent.
    final fond = find.ancestor(of: _page('CONNEXION'), matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == AppColors.fond));
    expect(fond, findsWidgets);
    expect(tester.getRect(fond.first), tester.getRect(_page('CONNEXION')));
    await tester.pumpAndSettle();
    expect(tester.getRect(_page('CONNEXION')), Offset.zero & _taille);
    expect(_page('ESPACE PRO'), findsNothing);
  });

  testWidgets('retour (flèche ou bouton retour) : même glissement en sens inverse, l\'écran précédent revient entier', (tester) async {
    final routeur = await _ouvrir(tester);
    routeur.push('/conducteur/connexion');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pump();
    final bords = await _suivre(tester, devant: 'CONNEXION', derriere: 'ESPACE PRO');
    for (var i = 1; i < bords.length; i++) {
      expect(bords[i], greaterThanOrEqualTo(bords[i - 1]), reason: 'l\'écran de connexion repart vers la droite');
    }
    await tester.pumpAndSettle();
    expect(_page('CONNEXION'), findsNothing);
    expect(tester.getRect(_page('ESPACE PRO')), Offset.zero & _taille);
  });

  testWidgets('glissement de retour d\'Android 16 : l\'écran ne suit plus le doigt ni ne se fige ; relâché, retour normal', (tester) async {
    final routeur = await _ouvrir(tester);
    routeur.push('/conducteur/connexion');
    await tester.pumpAndSettle();
    await _geste(tester, 'startBackGesture', 0);
    await _geste(tester, 'updateBackGestureProgress', 0.5);
    // Pendant le geste : l'écran reste entier et opaque, rien ne transparaît.
    expect(tester.getRect(_page('CONNEXION')), Offset.zero & _taille);
    expect(_opacite(tester, 'CONNEXION'), 1.0);
    expect(_page('ESPACE PRO'), findsNothing);
    await _geste(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(_page('CONNEXION'), findsNothing);
    expect(tester.getRect(_page('ESPACE PRO')), Offset.zero & _taille);
  });

  testWidgets('connexion qui aboutit pendant un glissement de retour : l\'accueil arrive net, rien ne reste figé', (tester) async {
    final routeur = await _ouvrir(tester);
    routeur.push('/conducteur/connexion');
    await tester.pumpAndSettle();
    await _geste(tester, 'startBackGesture', 0);
    await _geste(tester, 'updateBackGestureProgress', 0.4);
    routeur.go('/conducteur'); // la connexion aboutit
    await tester.pump();
    await tester.pump();
    await _suivre(tester, devant: 'COMPTE', derriere: 'CONNEXION');
    await _geste(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(tester.getRect(_page('COMPTE')), Offset.zero & _taille);
    expect(_page('CONNEXION'), findsNothing);
    expect(_page('ESPACE PRO'), findsNothing);
  });

  testWidgets('connexion réussie : l\'accueil, opaque, chasse l\'écran de connexion (bouton en chargement compris)', (tester) async {
    final routeur = await _ouvrir(tester);
    routeur.push('/conducteur/connexion');
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONNEXION')); // va à l'accueil, comme après « Se connecter »
    await tester.pump();
    await tester.pump();
    final bords = await _suivre(tester, devant: 'COMPTE', derriere: 'CONNEXION');
    expect(bords.first, greaterThan(0));
    await tester.pumpAndSettle();
    expect(tester.getRect(_page('COMPTE')), Offset.zero & _taille);
    expect(_page('CONNEXION'), findsNothing);
  });

  testWidgets('« Se déconnecter » depuis Compte puis « Conducteur » tout de suite : jamais deux écrans l\'un dans l\'autre', (tester) async {
    await _ouvrir(tester, depart: '/conducteur');
    await tester.tap(find.text('COMPTE')); // déconnexion : Espace Pro
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await _suivre(tester, devant: 'ESPACE PRO', derriere: 'COMPTE');
    await tester.tap(find.text('ESPACE PRO'), warnIfMissed: false); // « Conducteur » sans attendre
    await tester.pump();
    await tester.pump();
    await _suivre(tester, devant: 'CONNEXION', derriere: 'ESPACE PRO');
    await tester.pumpAndSettle();
    expect(tester.getRect(_page('CONNEXION')), Offset.zero & _taille);
    expect(_page('COMPTE'), findsNothing);
    expect(_page('ESPACE PRO'), findsNothing);
  });

  testWidgets('mouvement réduit (accessibilité) : changement d\'écran immédiat', (tester) async {
    await _ouvrir(tester, mouvementReduit: true);
    await tester.tap(find.text('ESPACE PRO'));
    await tester.pump();
    await tester.pump();
    expect(tester.getRect(_page('CONNEXION')), Offset.zero & _taille);
    expect(_opacite(tester, 'CONNEXION'), 1.0);
  });
}
