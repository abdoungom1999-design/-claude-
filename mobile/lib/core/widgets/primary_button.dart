import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Bouton d'action principal Sprint (Commander, Payer…) : dégradé vert
/// vibrant, texte Onyx (11:1), coins arrondis et lueur verte pour un rendu
/// premium sur fond sombre. Désactivé : surface grise, texte atténué, sans
/// lueur.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    // En chargement, le bouton garde sa couleur (l'action est en cours) ;
    // seul un bouton sans action est grisé.
    final desactive = onPressed == null && !isLoading;
    final couleurTexte = desactive ? AppColors.texteDiscret.withValues(alpha: 0.6) : AppColors.onyx;

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: desactive ? null : AppColors.degradeAction,
        color: desactive ? AppColors.carteHaute : null,
        border: desactive ? Border.all(color: AppColors.bordVerre) : null,
        boxShadow: desactive
            ? null
            : [
                BoxShadow(
                  color: AppColors.vert.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          splashColor: AppColors.onyx.withValues(alpha: 0.14),
          highlightColor: AppColors.onyx.withValues(alpha: 0.08),
          onTap: isLoading ? null : onPressed,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.onyx),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20, color: couleurTexte),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: couleurTexte,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
