import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/app.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/core/widgets/logo_sprint.dart';
import 'package:sprint/core/widgets/splash_sprint.dart';

/// Écran de démarrage Onyx : le même fond et le même logo doivent se
/// retrouver dans la page web, le manifeste, les images de démarrage iPhone
/// et les thèmes Android. Ces tests vérifient qu'ils restent d'accord.
void main() {
  const onyxHex = '0B0B0C';

  String lire(String chemin) => File(chemin).readAsStringSync();

  test('AppColors.onyx est la valeur partagée avec le web et Android', () {
    expect(AppColors.onyx.toARGB32(), 0xFF0B0B0C);
    expect(lire('web/index.html').toUpperCase(), contains('#$onyxHex'));
    expect(lire('android/app/src/main/res/values/colors.xml').toUpperCase(), contains('#$onyxHex'));
  });

  group('écran Flutter', () {
    testWidgets('fond Onyx et logo « S » au centre, rien d\'autre', (tester) async {
      await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: SplashSprint()));
      final fond = tester.widget<ColoredBox>(find.byType(ColoredBox));
      expect(fond.color, AppColors.onyx);
      expect(find.byType(LogoSprint), findsOneWidget);
      expect(find.bySemanticsLabel('Sprint'), findsOneWidget);
      final centre = tester.getCenter(find.byType(LogoSprint));
      expect(centre, tester.getCenter(find.byType(SplashSprint)));
      expect(tester.getSize(find.byType(LogoSprint)), const Size.square(96));
    });

    testWidgets('le logo se redessine à la taille demandée', (tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: LogoSprint(taille: 200)),
      ));
      expect(tester.getSize(find.byType(LogoSprint)), const Size.square(200));
    });

    testWidgets('l\'app place l\'écran de démarrage sous les pages : jamais d\'écran blanc, jamais visible par-dessus',
        (tester) async {
      await tester.pumpWidget(const SprintApp());
      expect(find.byType(SplashSprint), findsOneWidget);
      // La page d'accueil est au-dessus et le recouvre entièrement.
      expect(find.text('Continuer avec mon numéro'), findsOneWidget);
      final ordre = tester.elementList(find.byType(SplashSprint)).first;
      final pile = ordre.findAncestorWidgetOfExactType<Stack>()!;
      expect(pile.children.first, isA<SplashSprint>());
      expect(pile.children.length, 2);
    });
  });

  group('page web et PWA', () {
    final index = lire('web/index.html');

    test('l\'écran de démarrage est dans la page elle-même (avant tout chargement)', () {
      expect(index, contains('id="demarrage"'));
      expect(index, contains('<svg'));
      expect(RegExp(r'html,\s*body\s*\{[^}]*background:\s*#0B0B0C', caseSensitive: false).hasMatch(index), isTrue);
      expect(index, contains('flutter-first-frame'));
      expect(index, contains('<meta name="theme-color" content="#$onyxHex">'));
    });

    test('même logo que l\'app : mêmes coordonnées', () {
      const trace = 'M69 27C66 10 30 10 30 32C30 52 70 47 70 68C70 90 34 90 30 74';
      expect(index, contains(trace));
      expect(lire('web/splash/logo-s.svg'), contains(trace));
      expect(lire('lib/core/widgets/logo_sprint.dart'), contains('moveTo(69, 27)'));
      const traceAndroid = 'M69,27C66,10 30,10 30,32C30,52 70,47 70,68C70,90 34,90 30,74';
      expect(lire('android/app/src/main/res/drawable/ic_splash_s.xml'), contains(traceAndroid));
      expect(lire('android/app/src/main/res/drawable/ic_splash_s_v31.xml'), contains(traceAndroid));
    });

    test('manifeste : fond Onyx (écran de démarrage de la PWA Android)', () {
      final manifeste = lire('web/manifest.json');
      expect(manifeste, contains('"background_color": "#$onyxHex"'));
      expect(manifeste, contains('"theme_color": "#$onyxHex"'));
    });

    test('iPhone : une image de démarrage par taille d\'écran, à la taille exacte, fond Onyx', () {
      final liens = RegExp(
        r'<link rel="apple-touch-startup-image" href="(splash/[^"]+)"\s+media="\(device-width: (\d+)px\) and \(device-height: (\d+)px\) and \(-webkit-device-pixel-ratio: (\d)\) and \(orientation: portrait\)">',
      ).allMatches(index).toList();
      expect(liens.length, greaterThanOrEqualTo(12));
      final vus = <String>{};
      for (final lien in liens) {
        final fichier = File('web/${lien.group(1)}');
        expect(fichier.existsSync(), isTrue, reason: '${lien.group(1)} manquant');
        final largeur = int.parse(lien.group(2)!);
        final hauteur = int.parse(lien.group(3)!);
        final ratio = int.parse(lien.group(4)!);
        // En-tête PNG : largeur et hauteur en pixels aux octets 16 à 23.
        final octets = ByteData.sublistView(Uint8List.fromList(fichier.readAsBytesSync().sublist(0, 24)));
        expect(octets.getUint32(16), largeur * ratio, reason: '${lien.group(1)} : largeur');
        expect(octets.getUint32(20), hauteur * ratio, reason: '${lien.group(1)} : hauteur');
        expect(vus.add('$largeur x $hauteur @$ratio'), isTrue, reason: 'taille en double');
      }
    });
  });

  group('Android', () {
    const res = 'android/app/src/main/res';

    test('avant Android 12 : fond Onyx et logo au centre', () {
      for (final chemin in ['$res/drawable/launch_background.xml', '$res/drawable-v21/launch_background.xml']) {
        final xml = lire(chemin);
        expect(xml, contains('@color/onyx'), reason: chemin);
        expect(xml, contains('@drawable/ic_splash_s'), reason: chemin);
        expect(xml, contains('android:gravity="center"'), reason: chemin);
      }
      expect(File('$res/drawable/ic_splash_s.xml').existsSync(), isTrue);
    });

    test('Android 12 et plus, en clair comme en sombre : fond Onyx et logo', () {
      for (final chemin in ['$res/values-v31/styles.xml', '$res/values-night-v31/styles.xml']) {
        final xml = lire(chemin);
        expect(xml, contains('android:windowSplashScreenBackground">@color/onyx'), reason: chemin);
        expect(xml, contains('android:windowSplashScreenAnimatedIcon">@drawable/ic_splash_s_v31'), reason: chemin);
        expect(xml, contains('name="LaunchTheme"'), reason: chemin);
      }
      expect(File('$res/drawable/ic_splash_s_v31.xml').existsSync(), isTrue);
    });
  });
}
