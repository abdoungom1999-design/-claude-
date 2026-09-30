import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'logo_sprint.dart';

/// Briques de la charte « Onyx & Light » : fond très clair légèrement
/// teinté, cartes « verre » (blanc translucide, bord fin, flou), texte Onyx,
/// orange en simple accent. Utilisées écran par écran (migration
/// progressive) ; un écran migré est enveloppé dans [ThemeOnyxLight] pour
/// que ses champs et boutons prennent le style Onyx & Light, sans toucher
/// aux écrans pas encore migrés.
class ThemeOnyxLight extends InheritedWidget {
  const ThemeOnyxLight({super.key, required super.child});

  /// Vrai si l'écran courant est en style Onyx & Light.
  static bool actif(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ThemeOnyxLight>() != null;

  @override
  bool updateShouldNotify(ThemeOnyxLight ancien) => false;
}

/// Fond d'écran Onyx & Light : dégradé gris très clair vers blanc, avec deux
/// halos doux (orange en haut, gris en bas) qui donnent au verre quelque
/// chose à flouter.
class FondOnyxLight extends StatelessWidget {
  const FondOnyxLight({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.fondClairHaut, AppColors.fondClair],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(top: -140, right: -120, child: _Halo(taille: 380, couleur: AppColors.orange, opacite: 0.16)),
          const Positioned(bottom: -160, left: -140, child: _Halo(taille: 400, couleur: Color(0xFF8E8E93), opacite: 0.14)),
          child,
        ],
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo({required this.taille, required this.couleur, required this.opacite});

  final double taille;
  final Color couleur;
  final double opacite;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: taille,
        height: taille,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [couleur.withValues(alpha: opacite), couleur.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

/// Carte « verre » : blanc translucide sur fond flouté, bord fin, grands
/// arrondis, ombre très douce.
class CarteVerre extends StatelessWidget {
  const CarteVerre({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.rayon = 28});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double rayon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rayon),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 32, offset: Offset(0, 14))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(rayon),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.verre,
              borderRadius: BorderRadius.circular(rayon),
              border: Border.all(color: AppColors.bordVerre),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Logo Sprint (tuile de marbre noir et « S » de verre), avec une ombre douce
/// sur les écrans clairs.
class TuileLogo extends StatelessWidget {
  const TuileLogo({super.key, this.taille = 84});

  final double taille;

  @override
  Widget build(BuildContext context) => LogoSprint(taille: taille, ombre: true);
}
