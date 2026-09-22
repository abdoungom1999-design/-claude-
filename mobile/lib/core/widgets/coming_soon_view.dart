import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Vue "bientôt disponible" pour les fonctionnalités listées dans la
/// maquette (Réservation, Location, Aéroport, sections du menu Chauffeur)
/// qui n'ont pas encore de logique métier réelle côté backend. Choisi
/// délibérément plutôt que de simuler un faux flux complet pour un
/// service qui n'existe pas dans le modèle de données.
class ComingSoonView extends StatelessWidget {
  const ComingSoonView({
    super.key,
    required this.icon,
    required this.titre,
    this.message = 'Cette fonctionnalité arrive prochainement.',
  });

  final IconData icon;
  final String titre;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.orangeLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: AppColors.orange, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              titre,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
