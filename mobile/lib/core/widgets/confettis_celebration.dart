import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Pluie de confettis dorés et verts qui traverse tout l'écran (célébration de
/// l'activation d'un compte chauffeur). Dessinée à la main, sans paquet :
/// chaque confetti tombe de haut en bas avec un petit balancement et une
/// rotation, à partir d'un tirage fixe (même pluie à chaque fois, donc
/// testable). Ne capte aucun geste : à poser dans un `Stack`, au-dessus du
/// contenu.
///
/// Si l'appareil demande de réduire les animations, rien n'est dessiné.
class ConfettisCelebration extends StatefulWidget {
  const ConfettisCelebration({super.key, this.duree = const Duration(milliseconds: 2600), this.nombre = 90});

  /// Durée de la chute (au-delà, la pluie est terminée).
  final Duration duree;
  final int nombre;

  @override
  State<ConfettisCelebration> createState() => _ConfettisCelebrationState();
}

class _ConfettisCelebrationState extends State<ConfettisCelebration> with SingleTickerProviderStateMixin {
  late final AnimationController _chute = AnimationController(vsync: this, duration: widget.duree);
  late final List<_Confetti> _confettis = _tirer(widget.nombre);
  bool _lancee = false;

  // Les dorés restent dans le jaune d'or de la charte (teinte de 45° et plus,
  // comme les étoiles de notation) : le test de palette interdit tout orange.
  static const _couleurs = [
    AppColors.etoile, // or
    AppColors.alerte, // or vif
    Color(0xFFFFE680), // or clair
    Color(0xFFD9B230), // or foncé
    AppColors.vert,
    Color(0xFF5BF0A0), // vert clair
    Color(0xFF7DFFB3), // vert éclatant
  ];

  static List<_Confetti> _tirer(int nombre) {
    final hasard = Random(2026);
    return [
      for (var i = 0; i < nombre; i++)
        _Confetti(
          x: hasard.nextDouble(),
          retard: hasard.nextDouble() * 0.35,
          vitesse: 0.75 + hasard.nextDouble() * 0.6,
          taille: 6 + hasard.nextDouble() * 6,
          phase: hasard.nextDouble() * pi * 2,
          rotation: (hasard.nextDouble() - 0.5) * 14,
          couleur: _couleurs[hasard.nextInt(_couleurs.length)],
          rond: hasard.nextInt(4) == 0,
        ),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_lancee && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _lancee = true;
      _chute.forward();
    }
  }

  @override
  void dispose() {
    _chute.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          key: const ValueKey('confettis'),
          painter: _PeintreConfettis(_confettis, _chute),
        ),
      ),
    );
  }
}

class _Confetti {
  const _Confetti({
    required this.x,
    required this.retard,
    required this.vitesse,
    required this.taille,
    required this.phase,
    required this.rotation,
    required this.couleur,
    required this.rond,
  });

  final double x;
  final double retard;
  final double vitesse;
  final double taille;
  final double phase;
  final double rotation;
  final Color couleur;
  final bool rond;
}

class _PeintreConfettis extends CustomPainter {
  _PeintreConfettis(this.confettis, this.chute) : super(repaint: chute);

  final List<_Confetti> confettis;
  final Animation<double> chute;

  @override
  void paint(Canvas canvas, Size size) {
    final t = chute.value;
    final pinceau = Paint();
    for (final c in confettis) {
      final avancement = ((t - c.retard) / (1 - c.retard)).clamp(0.0, 1.0);
      if (avancement <= 0 || avancement >= 1) continue;
      final y = -20 + avancement * c.vitesse * (size.height + 60);
      final x = c.x * size.width + sin(c.phase + avancement * 7) * 18;
      // Les confettis s'effacent en fin de chute plutôt que de sortir d'un coup.
      final opacite = avancement > 0.85 ? (1 - avancement) / 0.15 : 1.0;
      pinceau.color = c.couleur.withValues(alpha: opacite.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(c.rotation * avancement + c.phase);
      if (c.rond) {
        canvas.drawCircle(Offset.zero, c.taille / 2, pinceau);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: c.taille, height: c.taille * 0.5), const Radius.circular(1.5)),
          pinceau,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PeintreConfettis ancien) => ancien.confettis != confettis;
}
