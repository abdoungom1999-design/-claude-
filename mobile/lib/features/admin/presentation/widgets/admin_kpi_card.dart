import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';

/// Carte KPI (Dashboard) : icône accentuée, grande valeur, libellé.
class AdminKpiCard extends StatelessWidget {
  const AdminKpiCard({
    super.key,
    required this.icon,
    required this.valeur,
    required this.label,
    this.accent = AppColors.vert,
    this.detail,
  });

  final IconData icon;
  final String valeur;
  final String label;
  final Color accent;

  /// Précision sous le libellé (ex. "12 cette semaine").
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(height: 18),
          Text(
            valeur,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.texteDiscret)),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail!, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: accent)),
          ],
        ],
      ),
    );
  }
}
