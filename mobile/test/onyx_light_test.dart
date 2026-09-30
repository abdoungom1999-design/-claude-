import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/app.dart';
import 'package:sprint/core/router/app_router.dart';
import 'package:sprint/core/router/app_routes.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/core/widgets/app_text_field.dart';
import 'package:sprint/core/widgets/onyx_light.dart';
import 'package:sprint/core/widgets/primary_button.dart';

/// Charte « Onyx & Light », écran par écran. Étape 1 : Bienvenue et
/// connexion. Les écrans pas encore migrés doivent rester inchangés.
void main() {
  Future<void> ouvrirApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    // Le routeur est unique pour toute l'app : on repart de l'accueil à
    // chaque test.
    appRouter.go(AppRoutes.welcome);
    await tester.pumpWidget(const SprintApp());
    await tester.pump();
  }

  group('Bienvenue', () {
    testWidgets('fond clair, logo dans une tuile Onyx, mêmes entrées qu\'avant, plus de photo', (tester) async {
      await ouvrirApp(tester);
      expect(find.byType(FondOnyxLight), findsOneWidget);
      expect(find.byType(TuileLogo), findsOneWidget);
      expect(find.byType(CarteVerre), findsOneWidget);
      expect(find.text('Sprint'), findsOneWidget);
      expect(find.text('Votre chauffeur en quelques secondes'), findsOneWidget);
      expect(find.text('Continuer avec mon numéro'), findsOneWidget);
      expect(find.text('Continuer avec mon email'), findsOneWidget);
      expect(find.text('Continuer avec Apple'), findsOneWidget);
      expect(find.text('Espace conducteur / admin'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, AppColors.fondClair);
    });

    testWidgets('le bouton principal est Onyx plein, les autres blancs', (tester) async {
      await ouvrirApp(tester);
      ElevatedButton bouton(String texte) => tester.widget<ElevatedButton>(
            find.ancestor(of: find.text(texte), matching: find.byType(ElevatedButton)),
          );
      expect(bouton('Continuer avec mon numéro').style!.backgroundColor!.resolve({}), AppColors.onyx);
      expect(bouton('Continuer avec mon email').style!.backgroundColor!.resolve({})!.a, greaterThan(0.85));
    });

    testWidgets('« Continuer avec mon numéro » mène à la connexion, la flèche « Retour » revient', (tester) async {
      await ouvrirApp(tester);
      await tester.tap(find.text('Continuer avec mon numéro'));
      await tester.pumpAndSettle();
      expect(find.text('Content de vous revoir'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Continuer avec mon numéro'), findsOneWidget);
    });

    testWidgets('« Espace conducteur / admin » ouvre le sélecteur', (tester) async {
      await ouvrirApp(tester);
      await tester.tap(find.text('Espace conducteur / admin'));
      await tester.pumpAndSettle();
      expect(find.text('Espace professionnel'), findsOneWidget);
      expect(find.text('Conducteur'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
    });
  });

  group('Connexion', () {
    Future<void> ouvrirConnexion(WidgetTester tester) async {
      await ouvrirApp(tester);
      await tester.tap(find.text('Continuer avec mon email'));
      await tester.pumpAndSettle();
    }

    testWidgets('titre, formulaire dans une carte « verre », liens conservés', (tester) async {
      await ouvrirConnexion(tester);
      expect(find.text('Content de vous revoir'), findsOneWidget);
      expect(find.text('Connectez-vous pour réserver une course ou envoyer un colis'), findsOneWidget);
      expect(find.byType(TuileLogo), findsOneWidget);
      expect(find.byType(CarteVerre), findsOneWidget);
      expect(find.text('Email ou numéro de téléphone'), findsOneWidget);
      expect(find.text('Mot de passe'), findsOneWidget);
      expect(find.text('Mot de passe oublié ?'), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
      expect(find.text('Pas encore de compte ? Créer un compte'), findsOneWidget);
      expect(find.text('Accès Admin'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('la validation des champs fonctionne toujours', (tester) async {
      await ouvrirConnexion(tester);
      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      expect(find.text('Email ou numéro requis'), findsOneWidget);
      expect(find.text('8 caractères minimum'), findsOneWidget);
    });

    testWidgets('le formulaire d\'inscription reprend le même style', (tester) async {
      await ouvrirConnexion(tester);
      await tester.tap(find.text('Pas encore de compte ? Créer un compte'));
      await tester.pumpAndSettle();
      expect(find.text('Créer un compte'), findsWidgets);
      expect(find.byType(CarteVerre), findsOneWidget);
      expect(find.byType(TuileLogo), findsOneWidget);
    });
  });

  group('Style limité aux écrans migrés', () {
    Widget hors(Widget enfant) => MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: enfant)));

    BoxDecoration decorationBouton(WidgetTester tester) {
      final conteneur = tester.widget<Container>(find.descendant(of: find.byType(PrimaryButton), matching: find.byType(Container)).first);
      return conteneur.decoration! as BoxDecoration;
    }

    testWidgets('bouton principal : orange partout ailleurs, Onyx dans un écran migré', (tester) async {
      await tester.pumpWidget(hors(PrimaryButton(label: 'Valider', onPressed: () {})));
      expect((decorationBouton(tester).gradient! as LinearGradient).colors, [AppColors.orange, AppColors.orangeDark]);

      await tester.pumpWidget(hors(ThemeOnyxLight(child: PrimaryButton(label: 'Valider', onPressed: () {}))));
      expect((decorationBouton(tester).gradient! as LinearGradient).colors, [AppColors.onyxClair, AppColors.onyx]);
    });

    testWidgets('champ : bordure orange partout ailleurs, Onyx dans un écran migré', (tester) async {
      InputDecoration decoration() => tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;

      await tester.pumpWidget(hors(const AppTextField(label: 'Nom', prefixIcon: Icons.person_outline)));
      expect((decoration().focusedBorder! as OutlineInputBorder).borderSide.color, AppColors.orange);

      await tester.pumpWidget(hors(const ThemeOnyxLight(child: AppTextField(label: 'Nom', prefixIcon: Icons.person_outline))));
      expect((decoration().focusedBorder! as OutlineInputBorder).borderSide.color, AppColors.onyx);
    });

    testWidgets('un écran non migré (Compte, etc.) n\'est pas en style Onyx & Light', (tester) async {
      late BuildContext contexte;
      await tester.pumpWidget(hors(Builder(builder: (c) {
        contexte = c;
        return const SizedBox();
      })));
      expect(ThemeOnyxLight.actif(contexte), isFalse);
    });
  });
}
