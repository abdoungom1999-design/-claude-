import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Moto Sprint vue de haut (style flat), tournée selon [cap] (degrés,
/// 0 = nord). Dessinée en vectoriel : nette à toutes les tailles, aucune
/// image à télécharger. Le contour blanc la détache de n'importe quel
/// fond de carte.
class MotoVueDessus extends StatelessWidget {
  const MotoVueDessus({
    super.key,
    this.cap,
    this.taille = 38,
    this.couleur = AppColors.vert,
    this.libelle = 'Moto Sprint à proximité',
  });

  /// Direction de la moto ; `null` : pointée vers le nord.
  final double? cap;

  /// Hauteur de la moto (la largeur en est la moitié environ).
  final double taille;

  /// Couleur de la tenue du pilote (vert Sprint par défaut).
  final Color couleur;

  /// Texte lu par les lecteurs d'écran.
  final String libelle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: libelle,
      child: Transform.rotate(
        angle: (cap ?? 0) * math.pi / 180,
        child: CustomPaint(
          size: Size(taille * 0.6, taille),
          painter: _PeintreMoto(couleur),
        ),
      ),
    );
  }
}

class _PeintreMoto extends CustomPainter {
  const _PeintreMoto(this.couleur);

  final Color couleur;

  static const _noir = Color(0xFF1E1E1E);
  static const _gris = Color(0xFF3A3A3A);

  @override
  void paint(Canvas canvas, Size size) {
    // Repère de dessin : 24 × 40, avant de la moto en haut.
    canvas.scale(size.width / 24, size.height / 40);

    RRect piece(double cx, double cy, double l, double h, [double? r]) =>
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy), width: l, height: h), Radius.circular(r ?? l / 2));

    final contour = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round;
    final ombre = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);

    final silhouette = <RRect>[
      piece(12, 5.5, 5, 9), // roue avant
      piece(12, 34.5, 6, 10), // roue arrière
      piece(12, 11, 19, 2.8, 1.4), // guidon
      piece(12, 21, 11, 24), // carénage et réservoir
      piece(12, 23, 15, 9, 4.5), // épaules du pilote
    ];

    // Ombre portée, puis contour blanc, puis les pièces.
    canvas.save();
    canvas.translate(1.2, 1.8);
    for (final p in silhouette) {
      canvas.drawRRect(p, ombre);
    }
    canvas.restore();
    for (final p in silhouette) {
      canvas.drawRRect(p, contour);
    }

    final plein = Paint();
    canvas.drawRRect(silhouette[0], plein..color = _noir);
    canvas.drawRRect(silhouette[1], plein..color = _noir);
    canvas.drawRRect(silhouette[2], plein..color = _gris);
    // Poignées et rétroviseurs.
    canvas.drawRRect(piece(3.4, 11, 3, 3.2, 1.2), plein..color = _noir);
    canvas.drawRRect(piece(20.6, 11, 3, 3.2, 1.2), plein..color = _noir);
    canvas.drawRRect(silhouette[3], plein..color = _gris);
    // Phare et feu arrière.
    canvas.drawRRect(piece(12, 9.2, 5, 2, 1), plein..color = const Color(0xFFFFF4D6));
    canvas.drawRRect(piece(12, 32.6, 4.6, 1.6, 0.8), plein..color = const Color(0xFFE53935));
    // Pilote : tenue Sprint, puis casque avec reflet.
    canvas.drawRRect(silhouette[4], plein..color = couleur);
    canvas.drawCircle(const Offset(12, 19.6), 4.3, plein..color = _noir);
    canvas.drawCircle(const Offset(10.7, 18.2), 1.3, plein..color = Colors.white.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(_PeintreMoto ancien) => ancien.couleur != couleur;
}
