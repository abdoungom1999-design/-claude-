import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Bouton rond « verre » sombre (flou, Onyx translucide, bord fin) : lisible
/// sur la carte comme sur n'importe quel fond. Commandes flottantes de
/// l'accueil client (notifications, « Me localiser »).
class BoutonRondVerre extends StatelessWidget {
  const BoutonRondVerre({super.key, required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;

  /// Infobulle, lue aussi par les lecteurs d'écran : le bouton n'a pas de texte.
  final String tooltip;
  final VoidCallback onTap;

  /// Diamètre du bouton, aussi réutilisé par l'avatar posé à côté.
  static const diametre = 44.0;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 20, offset: Offset(0, 8))],
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Material(
              color: AppColors.fond.withValues(alpha: 0.82),
              shape: const CircleBorder(side: BorderSide(color: AppColors.bordVerre)),
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: SizedBox(width: diametre, height: diametre, child: Icon(icon, size: 20, color: AppColors.texte)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
