import 'package:flutter/material.dart';
import 'onyx_vert.dart';

/// Carte flottante standard Sprint : « verre » sombre (voir [CarteVerre]),
/// coins arrondis, liseré fin et ombre profonde. Touchable si [onTap] est
/// fourni ; [contour] la cerne d'une ligne verte (élément sélectionné).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.contour,
    this.lueur = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? contour;
  final bool lueur;

  @override
  Widget build(BuildContext context) {
    final verre = CarteVerre(
      rayon: 24,
      padding: padding,
      contour: contour,
      lueur: lueur,
      child: SizedBox(width: double.infinity, child: child),
    );
    if (onTap == null) return verre;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: verre);
  }
}
