import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Courbe d'évolution des courses sur la semaine : simple graphique fait
/// maison (CustomPainter), sans dépendance de charting supplémentaire.
class AdminCourbeCourses extends StatelessWidget {
  const AdminCourbeCourses({
    super.key,
    required this.valeurs,
    required this.labels,
  });

  final List<int> valeurs;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 160,
          child: CustomPaint(
            painter: _CourbePainter(valeurs: valeurs),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: labels
              .map(
                (jour) => Text(
                  jour,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _CourbePainter extends CustomPainter {
  _CourbePainter({required this.valeurs});

  final List<int> valeurs;

  @override
  void paint(Canvas canvas, Size size) {
    if (valeurs.isEmpty) return;

    final maxValeur = valeurs.reduce((a, b) => a > b ? a : b).toDouble();
    final minValeur = valeurs.reduce((a, b) => a < b ? a : b).toDouble();
    final ecart = (maxValeur - minValeur).clamp(1, double.infinity);

    final stepX = valeurs.length > 1 ? size.width / (valeurs.length - 1) : 0.0;
    final points = <Offset>[
      for (var i = 0; i < valeurs.length; i++)
        Offset(
          stepX * i,
          size.height - ((valeurs[i] - minValeur) / ecart) * size.height * 0.85 - 8,
        ),
    ];

    // Lignes de grille horizontales, très discrètes.
    final peintureGrille = Paint()
      ..color = AppColors.greyBorder.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height / 3 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), peintureGrille);
    }

    // Zone sous la courbe, en dégradé orange qui s'estompe.
    final chemin = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      chemin.lineTo(point.dx, point.dy);
    }
    final chemineZone = Path.from(chemin)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      chemineZone,
      Paint()
        ..shader = LinearGradient(
          colors: [
            AppColors.orange.withValues(alpha: 0.28),
            AppColors.orange.withValues(alpha: 0.0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // La courbe elle-même.
    canvas.drawPath(
      chemin,
      Paint()
        ..color = AppColors.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Points sur chaque valeur.
    for (final point in points) {
      canvas.drawCircle(point, 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(
        point,
        4.5,
        Paint()
          ..color = AppColors.orange
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CourbePainter oldDelegate) =>
      oldDelegate.valeurs != valeurs;
}
