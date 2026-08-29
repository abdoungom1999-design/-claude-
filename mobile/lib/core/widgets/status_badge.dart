import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Tonalité d'un [StatusBadge]. `attention` (orange) attire l'œil sur une
/// action requise ; `neutre` (gris) décrit un état informatif ; `actif`
/// (noir plein) marque un état confirmé/en cours.
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
        background = AppColors.orangeLight;
        foreground = AppColors.orange;
        break;
      case StatusTone.actif:
        background = AppColors.text;
        foreground = AppColors.background;
        break;
      case StatusTone.neutre:
        background = AppColors.greyLight;
        foreground = AppColors.grey;
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
