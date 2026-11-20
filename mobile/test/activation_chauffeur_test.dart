import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/theme/app_theme.dart';
import 'package:sprint/core/widgets/confettis_celebration.dart';
import 'package:sprint/core/widgets/ecran_statut_onyx.dart';
import 'package:sprint/features/conducteur/presentation/conducteur_en_attente_page.dart';

const _titreAttente = 'Dossier en cours de vérification';
const _titreFete = 'Félicitations ! Votre compte chauffeur Sprint est activé';

class _Banc {
  final flux = StreamController<Map<String, dynamic>?>();
  int ouvertures = 0;
  int deconnexions = 0;

  Future<void> afficher(WidgetTester tester, {bool animationsReduites = false, Stream<Map<String, dynamic>?>? stream}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => unawaited(flux.close()));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.sombre,
      home: MediaQuery(
        data: MediaQueryData(size: const Size(390, 844), disableAnimations: animationsReduites),
        child: ConducteurEnAttentePage(
          onDeconnexion: () => deconnexions++,
          fluxProfil: stream ?? flux.stream,
          onActive: () => ouvertures++,
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> approuver(WidgetTester tester) async {
    flux.add({'statutValidation': 'valide'});
    await tester.pump(); // l'événement est livré
    await tester.pump(const Duration(milliseconds: 400)); // le fondu démarre puis se termine
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(); // l'ancien écran est retiré
  }
}

void main() {
  group('écran « Dossier en cours de vérification » : écoute en temps réel', () {
    testWidgets('tant que le dossier est en attente : l\'écran d\'avant, rien d\'autre', (tester) async {
      final banc = _Banc();
      await banc.afficher(tester);
      banc.flux.add({'statutValidation': 'en_attente'});
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(_titreAttente), findsOneWidget);
      expect(find.text('Se déconnecter'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      expect(find.byType(ConfettisCelebration), findsNothing);
      expect(find.text('Commencer'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(banc.ouvertures, 0);
    });

    testWidgets('l\'écran écoute le profil du chauffeur (et s\'arrête quand il disparaît)', (tester) async {
      final banc = _Banc();
      await banc.afficher(tester);
      expect(banc.flux.hasListener, isTrue);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(banc.flux.hasListener, isFalse);
    });

    testWidgets('autres statuts (refusé, absent, vide) : pas de célébration', (tester) async {
      final banc = _Banc();
      await banc.afficher(tester);
      for (final profil in <Map<String, dynamic>?>[
        {'statutValidation': 'rejete'},
        {'statutValidation': 'VALIDE'},
        {'statutCompte': 'actif'},
        null,
      ]) {
        banc.flux.add(profil);
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(find.text(_titreAttente), findsOneWidget);
      expect(find.text(_titreFete), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(banc.ouvertures, 0);
    });

    testWidgets('une erreur de lecture ne change rien : l\'attente reste affichée', (tester) async {
      final banc = _Banc();
      await banc.afficher(tester);
      banc.flux.addError(Exception('hors ligne'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(_titreAttente), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Et l'approbation est vue quand la connexion revient.
      await banc.approuver(tester);
      expect(find.text(_titreFete), findsOneWidget);
    });
  });

  group('approbation : célébration', () {
    testWidgets('dès l\'approbation : message, confettis, halo du logo, étapes illuminées et bouton « Commencer »', (tester) async {
      final banc = _Banc();
      await banc.afficher(tester);
      await banc.approuver(tester);

      expect(find.text(_titreFete), findsOneWidget);
      expect(find.text(_titreAttente), findsNothing);
      expect(find.text('Se déconnecter'), findsNothing);
      expect(find.text('Commencer'), findsOneWidget);
      expect(find.byType(ConfettisCelebration), findsOneWidget);
      expect(find.byKey(const ValueKey('confettis')), findsOneWidget);
      expect(find.byType(HaloLogoSprint), findsOneWidget);

      final etapes = tester.widget<EtapesDossier>(find.byType(EtapesDossier));
      expect(etapes.eclat, isTrue);
      expect(etapes.etapeCourante, 3);
      // Les trois pastilles sont terminées : une coche chacune, plus de sablier.
      expect(find.descendant(of: find.byType(EtapesDossier), matching: find.byIcon(Icons.check_rounded)), findsNWidgets(3));
      expect(find.byIcon(Icons.hourglass_top_rounded), findsNothing);
      expect(find.text('Compte activé'), findsOneWidget);
      expect(banc.ouvertures, 0, reason: 'l\'espace chauffeur ne s\'ouvre qu\'à la fin de la célébration');
    });

    testWidgets('l\'espace chauffeur s\'ouvre tout seul au bout de 2,5 secondes, une seule fois', (tester) async {
      final banc = _Banc();
      await banc.afficher(tester);
      banc.flux.add({'statutValidation': 'valide'});
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 2400));
      expect(banc.ouvertures, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(banc.ouvertures, 1);
      await tester.pump(const Duration(seconds: 10));
      expect(banc.ouvertures, 1);
    });

    testWidgets('« Commencer » ouvre tout de suite, et le minuteur ne rouvre pas une seconde fois', (tester) async {
      final banc = _Banc();
      await banc.afficher(tester);
      await banc.approuver(tester);

      await tester.tap(find.text('Commencer'));
      await tester.pump();
      expect(banc.ouvertures, 1);
      await tester.tap(find.text('Commencer'));
      await tester.pump(const Duration(seconds: 10));
      expect(banc.ouvertures, 1);
    });

    testWidgets('plusieurs mises à jour du profil pendant la fête : une seule célébration, une seule ouverture', (tester) async {
      final banc = _Banc();
      await banc.afficher(tester);
      banc.flux.add({'statutValidation': 'valide'});
      await tester.pump();
      banc.flux.add({'statutValidation': 'valide', 'telephone': '+221 77 000 00 00'});
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ConfettisCelebration), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(banc.ouvertures, 1);
    });

    testWidgets('dossier déjà approuvé à l\'arrivée sur l\'écran (premier événement) : célébration aussi', (tester) async {
      final banc = _Banc();
      await banc.afficher(tester, stream: Stream.value({'statutValidation': 'valide'}));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(_titreFete), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(banc.ouvertures, 1);
    });

    testWidgets('quitter l\'écran pendant la fête : pas d\'ouverture fantôme ni d\'erreur', (tester) async {
      final banc = _Banc();
      await banc.afficher(tester);
      await banc.approuver(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 5));
      expect(banc.ouvertures, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('animations réduites par l\'appareil : le message est là, pas de confettis', (tester) async {
      final banc = _Banc();
      await banc.afficher(tester, animationsReduites: true);
      await banc.approuver(tester);

      expect(find.text(_titreFete), findsOneWidget);
      expect(find.byKey(const ValueKey('confettis')), findsNothing);
      await tester.pump(const Duration(milliseconds: 2600));
      expect(banc.ouvertures, 1);
    });

    testWidgets('petit écran (320 px) : aucun débordement pendant la célébration', (tester) async {
      final banc = _Banc();
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => unawaited(banc.flux.close()));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.sombre,
        home: ConducteurEnAttentePage(onDeconnexion: () {}, fluxProfil: banc.flux.stream, onActive: () {}),
      ));
      banc.flux.add({'statutValidation': 'valide'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('composants partagés : les autres écrans ne changent pas', () {
    testWidgets('EtapesDossier sans éclat : mêmes étapes qu\'avant (sablier à l\'étape « Vérification »)', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: EtapesDossier(etapeCourante: 1))));
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    });

    testWidgets('EcranStatutOnyx sans halo : pas de halo autour du logo', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: EcranStatutOnyx(icone: Icons.info_outline, titre: 'Titre', texte: 'Texte'),
      ));
      expect(find.byType(HaloLogoSprint), findsNothing);
    });
  });
}
