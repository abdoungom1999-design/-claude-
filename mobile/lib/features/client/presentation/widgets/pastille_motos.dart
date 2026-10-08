import 'package:flutter/material.dart';
import '../../../../core/maps/proximite_service.dart';
import '../../../../core/theme/app_colors.dart';

/// Compteur posé sur la carte : « 4 motos disponibles · ~3 min ».
class PastilleMotos extends StatelessWidget {
  const PastilleMotos({super.key, required this.motos, required this.chargement});

  final Proximite motos;
  final bool chargement;

  String get _texte {
    if (chargement) return 'Recherche des motos…';
    final n = motos.motos.length;
    if (n == 0) return 'Aucune moto à proximité pour le moment';
    final approche = motos.approcheMinutes == null ? '' : ' · ~${motos.approcheMinutes} min';
    return '${n == 1 ? '1 moto disponible' : '$n motos disponibles'}$approche';
  }

  @override
  Widget build(BuildContext context) {
    final aucune = !chargement && motos.motos.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.fond.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.bordVerre),
        boxShadow: const [BoxShadow(color: AppColors.shadowSoft, blurRadius: 12, offset: Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: chargement || aucune ? AppColors.texteDiscret : AppColors.vert,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(_texte, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.texte)),
        ],
      ),
    );
  }
}
