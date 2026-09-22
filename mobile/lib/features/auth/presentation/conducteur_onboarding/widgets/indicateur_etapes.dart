import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';

/// Indicateur de progression du parcours d'inscription Chauffeur en 3
/// étapes : segments pleins pour les étapes franchies/actuelle, gris
/// pour celles à venir.
class IndicateurEtapes extends StatelessWidget {
  const IndicateurEtapes({
    super.key,
    required this.etapeActuelle,
    required this.labels,
  });

  final int etapeActuelle;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i != 0) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 5,
                  decoration: BoxDecoration(
                    color: i <= etapeActuelle ? AppColors.orange : AppColors.greyBorder,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < labels.length; i++)
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: i == etapeActuelle ? FontWeight.w700 : FontWeight.w500,
                  color: i <= etapeActuelle ? AppColors.orange : AppColors.grey,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
