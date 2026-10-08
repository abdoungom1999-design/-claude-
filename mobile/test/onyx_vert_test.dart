import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/app.dart';
import 'package:sprint/core/router/app_router.dart';
import 'package:sprint/core/router/app_routes.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/core/widgets/app_text_field.dart';
import 'package:sprint/core/widgets/onyx_vert.dart';
import 'package:sprint/core/widgets/primary_button.dart';

/// Charte « Onyx & Vert » : Bienvenue, connexion et briques partagées
/// (bouton d'action, champ de saisie, flou des cartes).
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
    testWidgets('fond Onyx, logo (tuile), mêmes entrées qu\'avant, plus de photo', (tester) async {
      await ouvrirApp(tester);
      expect(find.byType(FondOnyxVert), findsOneWidget);
      expect(find.byType(TuileLogo), findsOneWidget);
      expect(find.byType(CarteVerre), findsOneWidget);
      expect(find.text('Sprint'), findsOneWidget);
      expect(find.text('Votre chauffeur en quelques secondes'), findsOneWidget);
      expect(find.text('Continuer avec mon numéro'), findsOneWidget);
      expect(find.text('Continuer avec mon email'), findsOneWidget);
      expect(find.text('Continuer avec Apple'), findsOneWidget);
      expect(find.text('Espace conducteur / admin'), findsOneWidget);
      // Aucune photo : les seules images sont le logo embarqué (celui de la
      // page et celui de l'écran de démarrage placé dessous).
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images, isNotEmpty);
      expect(images.every((i) => i.image is AssetImage && (i.image as AssetImage).assetName == 'assets/logo/tuile.png'), isTrue);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, AppColors.fond);
    });

    testWidgets('le bouton principal est le bouton d\'action vert à texte Onyx, les autres en verre sombre', (tester) async {
      await ouvrirApp(tester);
      expect(find.widgetWithText(PrimaryButton, 'Continuer avec mon numéro'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Continuer avec mon numéro')).style?.color, AppColors.onyx);
      for (final texte in ['Continuer avec mon email', 'Continuer avec Apple']) {
        expect(find.ancestor(of: find.text(texte), matching: find.byType(PrimaryButton)), findsNothing, reason: texte);
        final style = tester.widget<ElevatedButton>(find.ancestor(of: find.text(texte), matching: find.byType(ElevatedButton))).style!;
        expect(style.backgroundColor!.resolve({}), AppColors.verre);
        expect(style.foregroundColor!.resolve({}), AppColors.texte);
      }
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
      // Aucune photo : les seules images sont le logo embarqué (celui de la
      // page et celui de l'écran de démarrage placé dessous).
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images, isNotEmpty);
      expect(images.every((i) => i.image is AssetImage && (i.image as AssetImage).assetName == 'assets/logo/tuile.png'), isTrue);
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

  group('Briques partagées', () {
    Widget hors(Widget enfant) => MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: enfant)));

    BoxDecoration decorationBouton(WidgetTester tester) {
      final conteneur = tester.widget<Container>(find.descendant(of: find.byType(PrimaryButton), matching: find.byType(Container)).first);
      return conteneur.decoration! as BoxDecoration;
    }

    testWidgets('bouton principal : dégradé vert, texte Onyx, grisé sans action', (tester) async {
      await tester.pumpWidget(hors(PrimaryButton(label: 'Valider', onPressed: () {})));
      expect((decorationBouton(tester).gradient! as LinearGradient).colors, [AppColors.vert, AppColors.vertFonce]);
      expect(tester.widget<Text>(find.text('Valider')).style?.color, AppColors.onyx);

      // Le même dans un écran en charte (le style ne dépend pas de l'habillage).
      await tester.pumpWidget(hors(ThemeOnyxVert(child: PrimaryButton(label: 'Valider', onPressed: () {}))));
      expect((decorationBouton(tester).gradient! as LinearGradient).colors, [AppColors.vert, AppColors.vertFonce]);

      await tester.pumpWidget(hors(const PrimaryButton(label: 'Valider', onPressed: null)));
      expect(decorationBouton(tester).gradient, isNull);
      expect(decorationBouton(tester).color, AppColors.carteHaute);
    });

    testWidgets('champ de saisie : contour vert au focus, rouge en erreur', (tester) async {
      InputDecoration decoration() => tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;

      await tester.pumpWidget(hors(const AppTextField(label: 'Nom', prefixIcon: Icons.person_outline)));
      expect((decoration().focusedBorder! as OutlineInputBorder).borderSide.color, AppColors.vert);
      expect((decoration().errorBorder! as OutlineInputBorder).borderSide.color, AppColors.danger);
      expect(decoration().fillColor, AppColors.verre);
    });

    testWidgets('le flou des cartes est actif par défaut et se coupe pour un écran dense', (tester) async {
      late bool parDefaut;
      late bool coupe;
      await tester.pumpWidget(hors(Builder(builder: (c) {
        parDefaut = ThemeOnyxVert.flouActif(c);
        return const SizedBox();
      })));
      expect(parDefaut, isTrue);

      await tester.pumpWidget(hors(ThemeOnyxVert(
        flou: false,
        child: Builder(builder: (c) {
          coupe = ThemeOnyxVert.flouActif(c);
          return const SizedBox();
        }),
      )));
      expect(coupe, isFalse);
    });
  });
}
