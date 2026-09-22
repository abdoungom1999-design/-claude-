import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_card.dart';

/// Tuile de statistique pour tableaux de bord (Admin, Conducteur) : icône
/// dans un badge coloré, grande valeur, libellé. Carte flottante standard
/// Sprint (ombre douce, coins arrondis).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.valeur,
    this.icon,
    this.accent = AppColors.orange,
  });

  final String label;
  final String valeur;
  final IconData? icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            valeur,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.grey),
          ),
        ],
      ),
    );
  }
}
