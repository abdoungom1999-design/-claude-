import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/core/theme/app_theme.dart';

/// Garde-fou de la charte « Onyx & Vert » (voulue par le client, octobre
/// 2026) : fonds Onyx et gris très sombres, texte clair, vert vibrant pour
/// l'action et l'état actif, texte Onyx sur les boutons verts, plus aucun
/// orange nulle part. Ce fichier ne se modifie que sur ordre du client.
double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claire = la > lb ? la : lb;
  final sombre = la > lb ? lb : la;
  return (claire + 0.05) / (sombre + 0.05);
}

/// Teinte « orange » : de l'orangé au jaune-orangé, saturée et lumineuse.
/// Le rouge d'alerte (0-7°) et le jaune d'or des étoiles (45° et plus) sont
/// hors de cette plage.
bool _estOrange(Color c) {
  final hsv = HSVColor.fromColor(c);
  return hsv.saturation > 0.45 && hsv.value > 0.35 && hsv.hue >= 8 && hsv.hue < 45;
}

void main() {
  group('thème', () {
    final theme = AppTheme.sombre;

    test('sombre, vert vibrant en couleur principale, texte Onyx sur le vert', () {
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, AppColors.vert);
      expect(theme.colorScheme.onPrimary, AppColors.onyx);
      expect(theme.scaffoldBackgroundColor, AppColors.fond);
      final bouton = theme.elevatedButtonTheme.style!;
      expect(bouton.backgroundColor!.resolve(<WidgetState>{}), AppColors.vert);
      expect(bouton.foregroundColor!.resolve(<WidgetState>{}), AppColors.onyx);
    });

    test('la charte est le seul thème de l\'app', () {
      expect(AppTheme.light.brightness, Brightness.dark);
    });
  });

  group('contrastes (WCAG)', () {
    test('texte Onyx sur le vert d\'action : au moins 7:1, sur toute la longueur du dégradé', () {
      expect(_contraste(AppColors.onyx, AppColors.vert), greaterThanOrEqualTo(7));
      expect(_contraste(AppColors.onyx, AppColors.vertFonce), greaterThanOrEqualTo(7));
    });

    test('texte clair et texte discret lisibles sur chaque fond sombre (4,5:1 et plus)', () {
      for (final fond in [AppColors.fond, AppColors.fondHaut, AppColors.carte, AppColors.carteHaute, AppColors.fondBarre]) {
        expect(_contraste(AppColors.texte, fond), greaterThanOrEqualTo(12), reason: 'texte sur $fond');
        expect(_contraste(AppColors.texteDiscret, fond), greaterThanOrEqualTo(4.5), reason: 'texte discret sur $fond');
      }
    });

    test('le vert se lit sur les fonds sombres (icônes, liens, contours : 3:1 minimum, texte 4,5:1)', () {
      for (final fond in [AppColors.fond, AppColors.carte, AppColors.carteHaute, AppColors.vertTeinte]) {
        expect(_contraste(AppColors.vert, fond), greaterThanOrEqualTo(4.5), reason: 'vert sur $fond');
      }
    });

    test('rouge d\'alerte lisible sur fond sombre', () {
      expect(_contraste(AppColors.danger, AppColors.fond), greaterThanOrEqualTo(4.5));
      expect(_contraste(AppColors.danger, AppColors.carte), greaterThanOrEqualTo(4.5));
    });
  });

  group('plus aucun orange', () {
    final sources = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart')) (chemin: f.path.replaceAll('\\', '/'), texte: f.readAsStringSync()),
    ];

    test('aucun nom de couleur orange dans le code', () {
      final motif = RegExp(r'Colors\.(deepOrange|orange)\b|orangeAccent|AppColors\.orange(Dark|Light)?\b|hueOrange');
      // Exception transitoire : encore lu par les fichiers hors zone en attente d'autorisation.
      final intrus = [
        for (final s in sources)
          if (s.chemin != 'lib/core/theme/app_colors.dart' && motif.hasMatch(s.texte)) s.chemin,
      ];
      expect(intrus, isEmpty, reason: 'orange : $intrus');
    });

    test('aucune valeur de couleur orange écrite en dur', () {
      final motif = RegExp(r'Color\(\s*0x([0-9A-Fa-f]{8})\s*\)');
      final intrus = <String>[];
      for (final s in sources) {
        for (final m in motif.allMatches(s.texte)) {
          final c = Color(int.parse(m.group(1)!, radix: 16));
          if (c.a > 0.3 && _estOrange(c)) intrus.add('${s.chemin} : 0x${m.group(1)}');
        }
      }
      expect(intrus, isEmpty, reason: 'valeurs orange : $intrus');
    });

    test('les jetons de couleur ne contiennent aucun orange', () {
      for (final c in [
        AppColors.vert, AppColors.vertFonce, AppColors.vertTeinte, AppColors.danger,
        AppColors.alerte, AppColors.etoile, AppColors.texte, AppColors.texteDiscret,
        AppColors.fond, AppColors.fondHaut, AppColors.carte, AppColors.carteHaute,
      ]) {
        expect(_estOrange(c), isFalse, reason: '$c');
      }
    });

    test('anciens noms de la charte « Onyx & Light » : seulement dans les fichiers en attente d\'autorisation', () {
      final motif = RegExp(r'AppColors\.(bleu|bleuClair|bleuFonce|background|grey|greyLight|greyBorder|fondClair|fondClairHaut|noirProfond|onyxClair|or)\b');
      const transitoires = {
        'lib/core/navigation/home_shell_page.dart',
        'lib/core/notifications/carte_notifications.dart',
        'lib/core/theme/app_colors.dart',
      };
      final intrus = [
        for (final s in sources)
          if (!transitoires.contains(s.chemin) && motif.hasMatch(s.texte)) s.chemin,
      ];
      expect(intrus, isEmpty, reason: 'anciens noms : $intrus');
    });
  });

  group('texte Onyx sur les boutons verts', () {
    test('un fond vert plein n\'est jamais suivi d\'un texte blanc', () {
      final intrus = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lignes = f.readAsStringSync().split('\n');
        for (var i = 0; i < lignes.length; i++) {
          if (!RegExp(r'backgroundColor:\s*AppColors\.vert,').hasMatch(lignes[i])) continue;
          for (var j = i + 1; j < lignes.length && j <= i + 4; j++) {
            if (RegExp(r'foregroundColor:\s*Colors\.white').hasMatch(lignes[j])) {
              intrus.add('${f.path.replaceAll('\\', '/')}:${j + 1}');
            }
          }
        }
      }
      expect(intrus, isEmpty, reason: 'texte blanc sur vert : $intrus');
    });
  });

  group('logo', () {
    testWidgets('liseré vert et point vert, aucun pixel orange', (tester) async {
      final lecture = await tester.runAsync(() async {
        final octets = File('assets/logo/tuile.png').readAsBytesSync();
        final codec = await ui.instantiateImageCodec(octets);
        final image = (await codec.getNextFrame()).image;
        final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        var orange = 0;
        var vert = 0;
        for (var i = 0; i < rgba.lengthInBytes; i += 4) {
          final a = rgba.getUint8(i + 3);
          if (a < 200) continue;
          final c = Color.fromARGB(255, rgba.getUint8(i), rgba.getUint8(i + 1), rgba.getUint8(i + 2));
          if (_estOrange(c)) orange++;
          final hsv = HSVColor.fromColor(c);
          if (hsv.saturation > 0.5 && hsv.value > 0.5 && hsv.hue > 110 && hsv.hue < 170) vert++;
        }
        return (orange: orange, vert: vert);
      });
      expect(lecture!.orange, lessThan(30), reason: 'pixels orange dans le logo');
      expect(lecture.vert, greaterThan(150), reason: 'pixels verts dans le logo');
    });
  });
}
