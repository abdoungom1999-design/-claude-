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
    // Aucun jour en surbrillance tant que rien n'a été gagné.
    final jourMax = maxValeur > 0 ? valeurs.indexOf(maxValeur.toInt()) : -1;

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
                      _court(valeurs[i]),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: i == jourMax ? FontWeight.w700 : FontWeight.w500,
                        color: i == jourMax ? AppColors.vert : AppColors.texteDiscret,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        // Semaine vide : barres à zéro, sans division par zéro.
                        height: maxValeur > 0 ? 90 * (valeurs[i] / maxValeur) : 0,
                        decoration: BoxDecoration(
                          gradient: i == jourMax
                              ? const LinearGradient(
                                  colors: [AppColors.vert, AppColors.vertFonce],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                )
                              : null,
                          color: i == jourMax ? null : AppColors.carteHaute,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      labels[i],
                      style: const TextStyle(fontSize: 11, color: AppColors.texteDiscret),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// "12k", "3,3k", "800".
  static String _court(int valeur) {
    if (valeur < 1000) return '$valeur';
    final milliers = valeur / 1000;
    return milliers >= 10 || milliers == milliers.roundToDouble()
        ? '${milliers.round()}k'
        : '${milliers.toStringAsFixed(1).replaceAll('.', ',')}k';
  }
}
