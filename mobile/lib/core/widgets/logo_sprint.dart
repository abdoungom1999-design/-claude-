import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Logo Sprint : la tuile de marbre noir, son « S » blanc de verre et son
/// liseré vert (image `assets/logo/tuile.png`, aux coins arrondis, fond
/// transparent), repris tel quel dans l'écran de démarrage, l'icône de l'app
/// et les écrans. L'image est produite à partir du logo source par
/// `tool/generer_icones.cjs`.
class LogoSprint extends StatelessWidget {
  const LogoSprint({super.key, this.taille = 128, this.ombre = false});

  /// Côté de la tuile, en pixels logiques.
  final double taille;

  /// Lueur verte douce autour de la tuile (sur les écrans sombres).
  final bool ombre;

  static const chemin = 'assets/logo/tuile.png';

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      chemin,
      width: taille,
      height: taille,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Sprint',
    );
    if (!ombre) return logo;
    // Lueur verte : un halo radial derrière la tuile (rien ne déborde du
    // widget, la mise en page ne change pas).
    return SizedBox(
      width: taille,
      height: taille,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: -taille * 0.55,
            top: -taille * 0.45,
            right: -taille * 0.55,
            bottom: -taille * 0.65,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [AppColors.vert.withValues(alpha: 0.30), AppColors.vert.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
          logo,
        ],
      ),
    );
  }
}
