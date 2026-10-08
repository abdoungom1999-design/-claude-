import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'primary_button.dart';

/// Dialog premium réutilisable : icône dans un badge dégradé, titre,
/// message, bouton d'action unique. Remplace les SnackBar plats et les
/// pages "bientôt disponible" pour les actions secondaires qui n'ont pas
/// encore de logique métier réelle, avec un rendu cohérent avec le reste
/// de l'app plutôt qu'un simple message texte.
class PremiumDialog extends StatelessWidget {
  const PremiumDialog({
    super.key,
    required this.icon,
    required this.titre,
    required this.message,
    this.labelBouton = 'Compris',
    this.succes = false,
  });

  final IconData icon;
  final String titre;
  final String message;
  final String labelBouton;

  /// true pour une confirmation de succès (pastille pleine) plutôt qu'une
  /// information neutre (pastille teintée, ex : "bientôt disponible").
  final bool succes;

  static Future<void> afficher(
    BuildContext context, {
    required IconData icon,
    required String titre,
    required String message,
    String labelBouton = 'Compris',
    bool succes = false,
  }) {
    return showDialog(
      context: context,
      builder: (_) => PremiumDialog(
        icon: icon,
        titre: titre,
        message: message,
        labelBouton: labelBouton,
        succes: succes,
      ),
    );
  }

  static Future<void> bientotDisponible(BuildContext context, String label) {
    return afficher(
      context,
      icon: Icons.rocket_launch_outlined,
      titre: label,
      message: 'Cette fonctionnalité arrive très prochainement sur Sprint.',
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.vert;
    final pastille = succes ? accent : accent.withValues(alpha: 0.14);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: AppColors.carte,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.bordVerre),
          boxShadow: [
            const BoxShadow(color: AppColors.shadow, blurRadius: 30, offset: Offset(0, 16)),
            BoxShadow(color: accent.withValues(alpha: 0.10), blurRadius: 40),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: pastille,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: succes ? AppColors.onyx : accent, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              titre,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.texte),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.texteDiscret),
            ),
            const SizedBox(height: 22),
            PrimaryButton(
              label: labelBouton,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
