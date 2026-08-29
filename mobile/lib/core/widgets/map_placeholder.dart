import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Emplacement réservé pour la future carte GPS (Phase 4). Affiche un
/// visuel neutre en attendant l'intégration d'un fournisseur de cartes.
class MapPlaceholder extends StatelessWidget {
  const MapPlaceholder({super.key, this.height = 220});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.greyLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.greyBorder),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.map_outlined, size: 40, color: AppColors.grey),
          const SizedBox(height: 8),
          Text(
            'Carte GPS - à venir',
            style: TextStyle(color: AppColors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
