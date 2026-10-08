import 'dart:convert';
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
    testWidgets('fond Onyx et logo au centre, rien d\'autre', (tester) async {
      await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: SplashSprint()));
      final fond = tester.widget<ColoredBox>(find.byType(ColoredBox));
      expect(fond.color, AppColors.onyx);
      expect(find.byType(LogoSprint), findsOneWidget);
      expect(find.bySemanticsLabel('Sprint'), findsOneWidget);
      expect(tester.getCenter(find.byType(LogoSprint)), tester.getCenter(find.byType(SplashSprint)));
      expect(tester.getSize(find.byType(LogoSprint)), const Size.square(128));
    });

    testWidgets('le logo est l\'image de la tuile, à la taille demandée', (tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: LogoSprint(taille: 200, ombre: true)),
      ));
      expect(tester.getSize(find.byType(LogoSprint)), const Size.square(200));
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, 'assets/logo/tuile.png');
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

    test('le logo de la page est intégré (aucun fichier à attendre) et c\'est bien la tuile', () {
      final correspondance = RegExp(r'<img id="demarrage-logo"[^>]*? src="data:image/webp;base64,([A-Za-z0-9+/=]+)"').firstMatch(index);
      expect(correspondance, isNotNull, reason: 'logo intégré manquant : node tool/generer_icones.cjs');
      final octets = base64Decode(correspondance!.group(1)!);
      expect(String.fromCharCodes(octets.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(octets.sublist(8, 12)), 'WEBP');
      expect(octets.length, lessThan(60 * 1024), reason: 'le logo intégré ralentirait la page');
    });

    test('icônes : images aux dimensions exactes, à partir du logo', () {
      final attendues = {
        'web/icons/Icon-192.png': 192,
        'web/icons/Icon-512.png': 512,
        'web/icons/Icon-maskable-192.png': 192,
        'web/icons/Icon-maskable-512.png': 512,
        'web/icons/apple-touch-icon.png': 180,
        'web/favicon.png': 64,
        'assets/logo/tuile.png': 512,
      };
      attendues.forEach((chemin, cote) {
        final octets = ByteData.sublistView(Uint8List.fromList(File(chemin).readAsBytesSync().sublist(0, 24)));
        expect(octets.getUint32(16), cote, reason: '$chemin : largeur');
        expect(octets.getUint32(20), cote, reason: '$chemin : hauteur');
      });
      expect(File('assets/logo/source-1024.jpg').existsSync(), isTrue);
      expect(File('tool/generer_icones.cjs').existsSync(), isTrue);
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
        expect(xml, contains('@drawable/splash_logo'), reason: chemin);
        expect(xml, contains('android:gravity="center"'), reason: chemin);
      }
      expect(File('$res/drawable-nodpi/splash_logo.png').existsSync(), isTrue);
    });

    test('Android 12 et plus, en clair comme en sombre : fond Onyx et logo', () {
      for (final chemin in ['$res/values-v31/styles.xml', '$res/values-night-v31/styles.xml']) {
        final xml = lire(chemin);
        expect(xml, contains('android:windowSplashScreenBackground">@color/onyx'), reason: chemin);
        expect(xml, contains('android:windowSplashScreenAnimatedIcon">@drawable/splash_logo_v31'), reason: chemin);
        expect(xml, contains('name="LaunchTheme"'), reason: chemin);
      }
      expect(File('$res/drawable/splash_logo_v31.xml').existsSync(), isTrue);
    });

    test('icône de l\'app : adaptative (logo) et anciennes tailles, plus d\'éclair', () {
      final adaptative = lire('$res/mipmap-anydpi-v26/ic_launcher.xml');
      expect(adaptative, contains('@mipmap/ic_launcher_foreground'));
      expect(adaptative, contains('@color/onyx'));
      expect(File('$res/drawable/ic_launcher_foreground.xml').existsSync(), isFalse, reason: 'ancien éclair');
      const tailles = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
      const premierPlan = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432};
      int largeur(String chemin) =>
          ByteData.sublistView(Uint8List.fromList(File(chemin).readAsBytesSync().sublist(0, 24))).getUint32(16);
      tailles.forEach((d, px) => expect(largeur('$res/mipmap-$d/ic_launcher.png'), px, reason: d));
      premierPlan.forEach((d, px) => expect(largeur('$res/mipmap-$d/ic_launcher_foreground.png'), px, reason: d));
    });

    test('icône des notifications : silhouette du « S », en blanc', () {
      final xml = lire('$res/drawable/ic_stat_sprint.xml');
      expect(xml, contains('android:fillColor="#FFFFFFFF"'));
      expect(xml, contains('android:pathData="M '));
      expect(xml, isNot(contains('M4,6 L10,12')), reason: 'ancienne icône');
    });

    test('la couleur des notifications est le vert Sprint (elle ne suit pas le fond de l\'icône)', () {
      expect(lire('$res/values/colors.xml'), contains('<color name="ic_launcher_background">#22E07A</color>'));
      expect(lire('$res/values/colors.xml').toUpperCase(), isNot(contains('#FF6600')), reason: 'plus aucun orange');
    });
  });
}
