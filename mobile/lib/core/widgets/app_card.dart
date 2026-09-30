import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'onyx_light.dart';

/// Carte flottante standard Sprint : fond blanc, ombre douce, coins
/// arrondis. Bordure très légère en complément de l'ombre (pas de plat).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Onyx & Light : carte « verre » (écrans migrés, voir [ThemeOnyxLight]).
    if (ThemeOnyxLight.actif(context)) {
      final verre = CarteVerre(rayon: 24, padding: padding, child: SizedBox(width: double.infinity, child: child));
      if (onTap == null) return verre;
      return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: verre);
    }
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.greyBorder.withValues(alpha: 0.6)),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSoft,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) {
      return card;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        child: card,
      ),
    );
  }
}
