import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Ligne de menu avec icône, libellé et chevron — utilisée pour les listes
/// de paramètres premium (écran Compte, menu Chauffeur). Pictogramme vert
/// dans une pastille teintée, libellé clair, pastille rouge à texte Onyx
/// pour un compteur.
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
                color: AppColors.vertTeinte,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.vert, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.texte),
              ),
            ),
            if (trailingBadge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  trailingBadge!,
                  style: const TextStyle(
                    color: AppColors.onyx,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.chevron_right_rounded, color: AppColors.texteDiscret),
          ],
        ),
      ),
    );
  }
}
