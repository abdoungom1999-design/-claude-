import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Snackbar stylée (icône verte, coins arrondis, flottante, liseré fin) pour
/// les notifications de confirmation — remplace les SnackBar texte brut par
/// défaut de Flutter.
class AppSnackbar {
  AppSnackbar._();

  static void succes(
    BuildContext context,
    String message, {
    IconData icon = Icons.check_circle_outline_rounded,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppColors.carteHaute,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.vert.withValues(alpha: 0.45)),
          ),
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              Icon(icon, color: AppColors.vert, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: AppColors.texte, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
