import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'onyx_light.dart';

/// Ligne de menu avec icône, libellé et chevron — utilisée pour les listes
/// de paramètres premium (écran Compte, menu Chauffeur).
class SectionListTile extends StatelessWidget {
  const SectionListTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.trailingBadge,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? trailingBadge;

  @override
  Widget build(BuildContext context) {
    final claire = ThemeOnyxLight.actif(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: claire ? AppColors.fondClair : AppColors.greyLight,
                borderRadius: BorderRadius.circular(claire ? 12 : 11),
              ),
              child: Icon(icon, color: claire ? AppColors.onyx : AppColors.text, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: claire ? FontWeight.w600 : FontWeight.w500,
                  color: claire ? AppColors.onyx : null,
                ),
              ),
            ),
            if (trailingBadge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  trailingBadge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right_rounded, color: claire ? AppColors.texteDiscret : AppColors.grey),
          ],
        ),
      ),
    );
  }
}
