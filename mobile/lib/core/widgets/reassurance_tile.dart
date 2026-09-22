import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_card.dart';

/// Petite tuile de réassurance (grille 4 cases sur l'écran Accueil) :
/// icône + libellé court.
class ReassuranceTile extends StatelessWidget {
  const ReassuranceTile({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, color: AppColors.orange, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
