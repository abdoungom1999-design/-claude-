import 'package:flutter/material.dart';

/// Logo Sprint : la tuile de marbre noir et son « S » de verre (image
/// `assets/logo/tuile.png`, aux coins arrondis, fond transparent), reprise
/// telle quelle dans l'écran de démarrage, l'icône de l'app et les écrans.
/// L'image est produite à partir du logo source par
/// `tool/generer_icones.cjs`.
class LogoSprint extends StatelessWidget {
  const LogoSprint({super.key, this.taille = 128, this.ombre = false});

  /// Côté de la tuile, en pixels logiques.
  final double taille;

  /// Ombre portée douce (sur les écrans clairs).
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
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(taille * 0.21),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 28, offset: Offset(0, 14))],
      ),
      child: logo,
    );
  }
}
