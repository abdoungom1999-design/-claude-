import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sprint/core/router/app_routes.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/core/theme/app_theme.dart';
import 'package:sprint/core/widgets/auth_scaffold.dart';
import 'package:sprint/features/auth/data/auth_repository.dart';
import 'package:sprint/features/auth/presentation/client_login_page.dart';
import 'package:sprint/features/auth/presentation/conducteur_onboarding/conducteur_onboarding_page.dart';
import 'package:sprint/features/auth/presentation/register_page.dart';
import 'package:sprint/features/onboarding/presentation/welcome_page.dart';

/// Directive du client (3 novembre 2026) : la navigation doit être exactement
/// aussi propre côté Client (Particulier) que côté chauffeur, aller comme
/// retour, sur Android comme sur iPhone : un écran chasse l'autre, jamais de
/// transparence, jamais de mouvement figé ni de deux écrans qui bougent en
/// sens opposés. Chaque cas est joué en Android puis en iPhone.
const _taille = Size(400, 800);
const _plateformes = TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS});

/// Connexion et inscription qui attendent qu'on les laisse aboutir.
class _Compte extends AuthRepository {
  final reponse = Completer<void>();

  @override
  Future<void> connecterClient({required String identifiant, required String motDePasse}) => reponse.future;

  @override
  Future<void> inscrireClient({
    required String nom,
    required String email,
    required String telephone,
    required String motDePasse,
  }) =>
      reponse.future;
}

/// Opacité réelle de ce que [cible] désigne : produit des fondus qui l'englobent.
double _opacite(WidgetTester tester, Finder cible) {
  var opacite = 1.0;
  final fondus = find.ancestor(of: cible, matching: find.byWidgetPredicate((w) => w is FadeTransition || w is Opacity));
  for (final element in fondus.evaluate()) {
    final w = element.widget;
    opacite *= w is FadeTransition ? w.opacity.value : (w as Opacity).opacity;
  }
  return opacite;
}

Widget _page(String nom, {List<(String, void Function(BuildContext))> boutons = const [], bool fondTransparent = false}) =>
    Builder(
      builder: (context) => Scaffold(
        key: ValueKey(nom),
        backgroundColor: fondTransparent ? Colors.transparent : null,
        appBar: AppBar(title: Text(nom)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [for (final (texte, action) in boutons) TextButton(onPressed: () => action(context), child: Text(texte))],
          ),
        ),
      ),
    );

/// Mêmes adresses que l'app côté Client : Bienvenue (vraie page), connexion
/// et inscription (vraies pages), accueil à onglets (Accueil, Compte), écran
/// « Commander une course ».
GoRouter _routeur(_Compte compte, {String depart = AppRoutes.welcome}) => GoRouter(
      initialLocation: depart,
      routes: [
        GoRoute(path: AppRoutes.welcome, builder: (_, __) => const WelcomePage()),
        GoRoute(path: AppRoutes.clientLogin, builder: (_, __) => ClientLoginPage(authRepository: compte)),
        GoRoute(path: AppRoutes.clientRegister, builder: (_, __) => RegisterPage(authRepository: compte)),
        GoRoute(path: AppRoutes.clientPassager, builder: (_, __) => _page('COMMANDER', fondTransparent: true)),
        StatefulShellRoute.indexedStack(
          builder: (context, state, onglets) => Scaffold(
            body: onglets,
            bottomNavigationBar: Row(
              children: [
                Expanded(child: TextButton(onPressed: () => onglets.goBranch(0), child: const Text('ONGLET ACCUEIL'))),
                Expanded(child: TextButton(onPressed: () => onglets.goBranch(1), child: const Text('ONGLET COMPTE'))),
              ],
            ),
          ),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (_, __) => _page('ACCUEIL', boutons: [('Commander', (c) => c.push(AppRoutes.clientPassager))]),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppRoutes.compteTab,
                builder: (_, __) => _page('COMPTE', boutons: [
                  ('Informations', (c) => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => _page('INFOS')))),
                  ('Se déconnecter', (c) => c.go(AppRoutes.welcome)),
                ]),
              ),
            ]),
          ],
        ),
      ],
    );

Future<GoRouter> _ouvrir(WidgetTester tester, _Compte compte, {String depart = AppRoutes.welcome}) async {
  tester.view.physicalSize = _taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final routeur = _routeur(compte, depart: depart);
  await tester.pumpWidget(MaterialApp.router(routerConfig: routeur, theme: AppTheme.sombre));
  await tester.pumpAndSettle();
  return routeur;
}

/// Suit la transition image par image jusqu'à la fin : rien de transparent,
/// et les écrans [quiNeReculentPas] ne repartent jamais vers la droite (pas
/// d'écran refermé pendant que le suivant arrive).
Future<void> _suivre(WidgetTester tester, {required List<Finder> visibles, List<Finder> quiNeReculentPas = const []}) async {
  for (var i = 0; i < 12; i++) {
    for (final f in visibles) {
      if (f.evaluate().isNotEmpty) expect(_opacite(tester, f), 1.0, reason: 'image $i');
    }
    for (final f in quiNeReculentPas) {
      if (f.evaluate().isNotEmpty) {
        expect(tester.getRect(f).left, lessThanOrEqualTo(0.5), reason: 'repart vers la droite, image $i');
      }
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Future<void> _ouvrirConnexion(WidgetTester tester) async {
  await tester.tap(find.text('Continuer avec mon numéro'));
  await tester.pumpAndSettle();
  expect(find.text('Content de vous revoir'), findsOneWidget);
}

Future<void> _remplirConnexion(WidgetTester tester) async {
  final champs = find.byType(TextFormField);
  await tester.enterText(champs.at(0), 'awa@test.sn');
  await tester.enterText(champs.at(1), 'motdepasse1');
}

void main() {
  testWidgets('connexion Client réussie : l\'accueil chasse la connexion en un seul mouvement (pas de retour à Bienvenue)',
      (tester) async {
    final compte = _Compte();
    await _ouvrir(tester, compte);
    await _ouvrirConnexion(tester);
    await _remplirConnexion(tester);
    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    compte.reponse.complete();
    await tester.pump();
    await tester.pump();
    await _suivre(
      tester,
      visibles: [_pageCle('ACCUEIL'), find.byType(ClientLoginPage)],
      quiNeReculentPas: [find.byType(ClientLoginPage)],
    );
    expect(find.text('ACCUEIL'), findsWidgets);
    expect(find.byType(ClientLoginPage), findsNothing);
    expect(find.byType(WelcomePage), findsNothing);
  }, variant: _plateformes);

  testWidgets('inscription Client réussie : l\'accueil arrive en un seul mouvement, le message de confirmation s\'affiche',
      (tester) async {
    final compte = _Compte();
    await _ouvrir(tester, compte);
    await _ouvrirConnexion(tester);
    await tester.tap(find.text('Pas encore de compte ? Créer un compte'));
    await tester.pumpAndSettle();
    final champs = find.byType(TextFormField);
    for (final (i, valeur) in ['Awa Ndiaye', 'awa@test.sn', '+221770000000', 'motdepasse1', 'motdepasse1'].indexed) {
      await tester.enterText(champs.at(i), valeur);
    }
    await tester.ensureVisible(find.text('Créer mon compte'));
    await tester.tap(find.text('Créer mon compte'));
    await tester.pump();
    compte.reponse.complete();
    await tester.pump();
    await tester.pump();
    await _suivre(
      tester,
      visibles: [_pageCle('ACCUEIL'), find.byType(RegisterPage)],
      quiNeReculentPas: [find.byType(RegisterPage), find.byType(ClientLoginPage)],
    );
    expect(find.byType(RegisterPage), findsNothing);
    expect(find.byType(ClientLoginPage), findsNothing);
    expect(find.text('ACCUEIL'), findsWidgets);
    expect(find.textContaining('Un email de confirmation vous a été envoyé'), findsOneWidget);
  }, variant: _plateformes);

  testWidgets('connexion ou inscription Client en cours : ni retour ni glissement de retour', (tester) async {
    final compte = _Compte();
    await _ouvrir(tester, compte);
    await _ouvrirConnexion(tester);
    final route = ModalRoute.of(tester.element(find.text('Content de vous revoir')))!;
    expect(route.popGestureEnabled, isTrue);
    await _remplirConnexion(tester);
    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    expect(route.popGestureEnabled, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Content de vous revoir'), findsOneWidget);
    compte.reponse.complete();
    await tester.pumpAndSettle();
    expect(find.text('ACCUEIL'), findsWidgets);
  }, variant: _plateformes);

  testWidgets('accueil › « Commander » › retour : un écran chasse l\'autre, à l\'aller comme au retour', (tester) async {
    await _ouvrir(tester, _Compte(), depart: AppRoutes.home);
    await tester.tap(find.text('Commander'));
    await tester.pump();
    await tester.pump();
    // Écran au fond transparent : rien ne transparaît, il est posé sur le fond Onyx.
    final fond = find.ancestor(
      of: _pageCle('COMMANDER'),
      matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == AppColors.fond),
    );
    expect(fond, findsWidgets);
    await _suivre(tester, visibles: [_pageCle('COMMANDER'), _pageCle('ACCUEIL')]);
    expect(tester.getRect(_pageCle('COMMANDER')), Offset.zero & _taille);

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iPhone : glissement natif depuis le bord gauche, sur l'écran réel.
      final geste = await tester.startGesture(const Offset(5, 300));
      for (var i = 0; i < 6; i++) {
        await geste.moveBy(const Offset(40, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(_opacite(tester, _pageCle('COMMANDER')), 1.0);
      }
      await geste.up();
    } else {
      await tester.binding.handlePopRoute(); // bouton ou geste de retour d'Android
    }
    await tester.pump();
    await _suivre(tester, visibles: [_pageCle('COMMANDER'), _pageCle('ACCUEIL')]);
    expect(_pageCle('COMMANDER'), findsNothing);
    expect(tester.getRect(_pageCle('ACCUEIL')).left, 0);
  }, variant: _plateformes);

  testWidgets('onglet Compte › sous-page › retour : la sous-page se referme, l\'onglet reste', (tester) async {
    await _ouvrir(tester, _Compte(), depart: AppRoutes.compteTab);
    await tester.tap(find.text('Informations'));
    await tester.pump();
    await tester.pump();
    await _suivre(tester, visibles: [_pageCle('INFOS'), _pageCle('COMPTE')]);
    expect(find.text('ONGLET COMPTE'), findsOneWidget, reason: 'la barre d\'onglets reste en place');
    await tester.binding.handlePopRoute();
    await tester.pump();
    await _suivre(tester, visibles: [_pageCle('INFOS'), _pageCle('COMPTE')]);
    expect(_pageCle('INFOS'), findsNothing);
    expect(tester.getRect(_pageCle('COMPTE')).left, 0);
  }, variant: _plateformes);

  testWidgets('« Se déconnecter » : Bienvenue chasse l\'accueil, net', (tester) async {
    await _ouvrir(tester, _Compte(), depart: AppRoutes.compteTab);
    await tester.tap(find.text('Se déconnecter'));
    await tester.pump();
    await tester.pump();
    await _suivre(tester, visibles: [find.byType(WelcomePage), _pageCle('COMPTE')]);
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(_pageCle('COMPTE'), findsNothing);
  }, variant: _plateformes);

  testWidgets('gabarit des écrans de connexion : retour suspendu seulement pendant l\'opération', (tester) async {
    tester.view.physicalSize = _taille;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final enCours = ValueNotifier(true);
    final cle = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: cle, theme: AppTheme.sombre, home: const Scaffold(body: Text('DESSOUS'))));
    cle.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => ValueListenableBuilder<bool>(
        valueListenable: enCours,
        builder: (_, valeur, __) => AuthScaffold(
          icon: Icons.person_outline,
          title: 'Connexion',
          subtitle: '',
          form: const SizedBox(),
          enCours: valeur,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Connexion'), findsOneWidget, reason: 'bloqué pendant l\'opération');
    enCours.value = false;
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('DESSOUS'), findsOneWidget);
  });

  testWidgets('inscription chauffeur : retour possible tant que rien n\'est en cours (garde en place)', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.sombre, home: const ConducteurOnboardingPage()));
    final garde = tester.widget<PopScope>(
      find.ancestor(of: find.byType(Scaffold).first, matching: find.byType(PopScope)).first,
    );
    expect(garde.canPop, isTrue);
  });
}

Finder _pageCle(String nom) => find.byKey(ValueKey(nom));
