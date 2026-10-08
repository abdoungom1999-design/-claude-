import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Tonalité d'un [StatusBadge]. `attention` (vert teinté) attire l'œil sur
/// une action requise ; `neutre` (gris) décrit un état informatif ; `actif`
/// (vert plein, texte Onyx) marque un état confirmé ou en cours.
enum StatusTone { attention, neutre, actif }

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;

    switch (tone) {
      case StatusTone.attention:
        background = AppColors.vertTeinte;
        foreground = AppColors.vert;
        break;
      case StatusTone.actif:
        background = AppColors.vert;
        foreground = AppColors.onyx;
        break;
      case StatusTone.neutre:
        background = AppColors.carteHaute;
        foreground = AppColors.texteDiscret;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
