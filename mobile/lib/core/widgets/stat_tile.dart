import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'onyx_vert.dart';

/// Tuile de statistique pour tableaux de bord (Admin, Conducteur) : icône
/// dans une pastille teintée, grande valeur claire, libellé discret, sur une
/// carte de verre sombre.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.valeur,
    this.icon,
    this.accent = AppColors.vert,
  });

  final String label;
  final String valeur;
  final IconData? icon;

  /// Couleur de la pastille et du pictogramme (vert par défaut ; gris
  /// [AppColors.texteDiscret] pour une valeur à zéro ou neutre).
  final Color accent;

  @override
  Widget build(BuildContext context) {
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
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(height: 12),
          ],
          Text(valeur, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.texte)),
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
}
