import 'dart:math';

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Énorme bouton rond flottant pour basculer En ligne / Hors ligne.
/// Hors ligne : halo orange qui respire lentement (pulsation), pour
/// inviter au tap sans être agressif. En ligne : l'animation se
/// transforme en radar high-tech (anneaux concentriques + balayage
/// rotatif), pour une lecture immédiate "je cherche des clients".
class BoutonEnLigneCirculaire extends StatefulWidget {
  const BoutonEnLigneCirculaire({
    super.key,
    required this.enLigne,
    required this.onTap,
  });

  final bool enLigne;
  final VoidCallback onTap;

  @override
  State<BoutonEnLigneCirculaire> createState() =>
      _BoutonEnLigneCirculaireState();
}

class _BoutonEnLigneCirculaireState extends State<BoutonEnLigneCirculaire>
    with TickerProviderStateMixin {
  late final AnimationController _radarController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _radarController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.enLigne)
            AnimatedBuilder(
              animation: _radarController,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: _radarController.value * 2 * pi,
                      child: CustomPaint(
                        size: const Size(210, 210),
                        painter: _BalayageRadarPainter(),
                      ),
                    ),
                    _CercleRadar(progression: _radarController.value),
                    _CercleRadar(progression: (_radarController.value + 0.33) % 1.0),
                    _CercleRadar(progression: (_radarController.value + 0.66) % 1.0),
                  ],
                );
              },
            )
          else
            AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_glowController.value);
                return Container(
                  width: 150 + t * 46,
                  height: 150 + t * 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.orange.withValues(alpha: 0.16 + t * 0.28),
                        blurRadius: 32 + t * 24,
                        spreadRadius: 2 + t * 12,
                      ),
                    ],
                  ),
                );
              },
            ),
          GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutBack,
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: widget.enLigne
                      ? const [AppColors.orange, AppColors.orangeDark]
                      : const [AppColors.noirProfondClair, AppColors.noirProfond],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white, width: 5),
                boxShadow: [
                  BoxShadow(
                    color: (widget.enLigne ? AppColors.orange : Colors.black)
                        .withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: widget.enLigne
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bolt_rounded, color: Colors.white, size: 34),
                        SizedBox(height: 4),
                        Text(
                          'EN LIGNE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'GO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Passer en ligne',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CercleRadar extends StatelessWidget {
  const _CercleRadar({required this.progression});

  final double progression;

  @override
  Widget build(BuildContext context) {
    final taille = 118 + progression * 72;
    final opacite = (1 - progression).clamp(0.0, 1.0) * 0.5;

    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.orange.withValues(alpha: opacite),
          width: 2,
        ),
      ),
    );
  }
}

/// Fine ligne de balayage rotative (façon écran radar), pour renforcer
/// l'effet "high-tech" une fois en ligne.
class _BalayageRadarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final rayon = size.width / 2;
    final rect = Rect.fromCircle(center: centre, radius: rayon);
    final peinture = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: pi / 3.5,
        colors: [
          AppColors.orange.withValues(alpha: 0.0),
          AppColors.orange.withValues(alpha: 0.4),
        ],
      ).createShader(rect);
    canvas.drawArc(rect, 0, pi / 3.5, true, peinture);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
