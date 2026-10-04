import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'onyx_light.dart';

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
    if (ThemeOnyxLight.actif(context)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: CarteVerre(
            rayon: 28,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: AppColors.fondClair, borderRadius: BorderRadius.circular(24)),
                  child: Icon(icon, color: AppColors.onyx, size: 30),
                ),
                const SizedBox(height: 18),
                Text(
                  titre,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.onyx),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.texteDiscret),
                ),
              ],
            ),
          ),
        ),
      );
    }
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
                color: AppColors.bleuClair,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: AppColors.bleu, size: 32),
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
