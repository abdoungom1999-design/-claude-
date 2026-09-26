import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/statut_compte.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../compte/presentation/centre_aide_page.dart';

/// Écran affiché au chauffeur dont le compte a été suspendu ou banni par
/// l'Admin (`statutCompte`, voir [StatutCompte]). Le chauffeur est déjà
/// déconnecté quand cet écran apparaît (voir le "Gardien" de
/// `ConducteurShellPage`) : il ne peut que lire le motif et quitter.
class ConducteurCompteBloquePage extends StatelessWidget {
  const ConducteurCompteBloquePage({super.key, required this.statutCompte});

  final String statutCompte;

  @override
  Widget build(BuildContext context) {
    final banni = statutCompte == StatutCompte.banni;
    final couleur = banni ? Colors.red.shade700 : AppColors.orange;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(banni ? Icons.block_rounded : Icons.pause_circle_outline_rounded, color: couleur, size: 54),
              ),
              const SizedBox(height: 30),
              Text(
                banni ? 'Compte désactivé' : 'Compte suspendu',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              Text(
                banni
                    ? "Votre compte chauffeur a été définitivement désactivé par l'équipe du Groupe Santine. "
                        "Vous ne pouvez plus accéder à l'application."
                    : "Votre compte chauffeur a été suspendu par l'équipe du Groupe Santine. Vous ne pouvez "
                        'plus prendre de courses pour le moment. Contactez le support pour en connaître la raison.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.grey, height: 1.6),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CentreAidePage()),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  side: const BorderSide(color: AppColors.greyBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  'Contacter le support',
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go(AppRoutes.espacePro),
                child: const Text(
                  "Retour à l'accueil",
                  style: TextStyle(color: AppColors.grey, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
