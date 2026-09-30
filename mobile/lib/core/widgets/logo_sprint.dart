import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Logo Sprint : un « S » géométrique blanc, terminé par un point orange
/// (la destination). Dessiné en code, à la même géométrie que
/// `web/splash/logo-s.svg` et `android/.../drawable/ic_splash_s.xml`, pour
/// que l'écran de démarrage web, Android et l'app se superposent sans
/// décalage. À changer aux trois endroits à la fois.
class LogoSprint extends StatelessWidget {
  const LogoSprint({super.key, this.taille = 96, this.couleurS = Colors.white, this.couleurPoint = AppColors.orange});

  final double taille;
  final Color couleurS;
  final Color couleurPoint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sprint',
      image: true,
      child: CustomPaint(
        size: Size.square(taille),
        painter: _LogoPainter(couleurS: couleurS, couleurPoint: couleurPoint),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({required this.couleurS, required this.couleurPoint});

  final Color couleurS;
  final Color couleurPoint;

  @override
  void paint(Canvas canvas, Size size) {
    final echelle = size.width / 100;
    canvas.save();
    canvas.scale(echelle);

    final s = Path()
      ..moveTo(69, 27)
      ..cubicTo(66, 10, 30, 10, 30, 32)
      ..cubicTo(30, 52, 70, 47, 70, 68)
      ..cubicTo(70, 90, 34, 90, 30, 74);
    canvas.drawPath(
      s,
      Paint()
        ..color = couleurS
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.drawCircle(const Offset(30, 74), 6.4, Paint()..color = couleurPoint..isAntiAlias = true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter ancien) => ancien.couleurS != couleurS || ancien.couleurPoint != couleurPoint;
}
