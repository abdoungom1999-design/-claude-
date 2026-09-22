import 'package:flutter/material.dart';

/// Snackbar stylée (icône, coins arrondis, flottante) pour les
/// notifications de confirmation — remplace les SnackBar texte brut par
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
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
