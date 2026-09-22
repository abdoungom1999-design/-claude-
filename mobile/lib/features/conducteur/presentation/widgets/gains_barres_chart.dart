import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Graphique à barres "maison" (simples Containers redimensionnés) pour
/// visualiser les gains par jour de la semaine.
class GainsBarresChart extends StatelessWidget {
  const GainsBarresChart({
    super.key,
    required this.valeurs,
    required this.labels,
  });

  final List<int> valeurs;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final maxValeur = valeurs.reduce((a, b) => a > b ? a : b).toDouble();
    final jourMax = valeurs.indexOf(valeurs.reduce((a, b) => a > b ? a : b));

    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < valeurs.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${(valeurs[i] / 1000).toStringAsFixed(0)}k',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: i == jourMax ? FontWeight.w700 : FontWeight.w500,
                        color: i == jourMax ? AppColors.orange : AppColors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        height: 90 * (valeurs[i] / maxValeur),
                        decoration: BoxDecoration(
                          gradient: i == jourMax
                              ? const LinearGradient(
                                  colors: [AppColors.orange, AppColors.orangeDark],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                )
                              : null,
                          color: i == jourMax ? null : AppColors.greyLight,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      labels[i],
                      style: const TextStyle(fontSize: 11, color: AppColors.grey),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
