import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Bouton principal du conducteur pour basculer En Ligne / Hors Ligne.
/// Volontairement très visible : pleine largeur, couleur pleine, icône
/// large, comme demandé pour le tableau de bord Conducteur.
class OnlineToggleButton extends StatelessWidget {
  const OnlineToggleButton({
    super.key,
    required this.enLigne,
    required this.onChanged,
  });

  final bool enLigne;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!enLigne),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        height: 88,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: enLigne ? AppColors.orange : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: enLigne ? AppColors.orange : AppColors.greyBorder,
            width: 1.5,
          ),
          boxShadow: enLigne
              ? [
                  BoxShadow(
                    color: AppColors.orange.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.power_settings_new_rounded,
              size: 36,
              color: enLigne ? AppColors.background : AppColors.text,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    enLigne ? 'EN LIGNE' : 'HORS LIGNE',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: enLigne ? AppColors.background : AppColors.text,
                    ),
                  ),
                  Text(
                    enLigne
                        ? 'Vous recevez des demandes de course'
                        : 'Touchez pour vous mettre en ligne',
                    style: TextStyle(
                      fontSize: 13,
                      color: enLigne
                          ? AppColors.background.withValues(alpha: 0.85)
                          : AppColors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
