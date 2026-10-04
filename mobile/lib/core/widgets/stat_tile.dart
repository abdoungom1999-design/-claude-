import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_card.dart';
import 'onyx_light.dart';

/// Tuile de statistique pour tableaux de bord (Admin, Conducteur) : icône
/// dans un badge coloré, grande valeur, libellé. Carte flottante standard
/// Sprint (ombre douce, coins arrondis).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.valeur,
    this.icon,
    this.accent = AppColors.bleu,
  });

  final String label;
  final String valeur;
  final IconData? icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    // Onyx & Light (écran Compte) : verre clair, pictogramme et chiffres Onyx.
    if (ThemeOnyxLight.actif(context)) {
      return CarteVerre(
        rayon: 22,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: AppColors.bleuClair, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: AppColors.bleu, size: 18),
              ),
              const SizedBox(height: 12),
            ],
            Text(valeur, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.onyx)),
            const SizedBox(height: 3),
            // « Réservations » tient sur une ligne, quitte à réduire un peu.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 11.5, color: AppColors.texteDiscret)),
            ),
          ],
        ),
      );
    }
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
