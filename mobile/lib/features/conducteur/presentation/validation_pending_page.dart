import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/data/auth_repository.dart';
import '../../compte/presentation/centre_aide_page.dart';

/// Écran de blocage affiché tant que le dossier du chauffeur (documents
/// + véhicule soumis via [ConducteurOnboardingPage]) n'a pas été
/// validé : il ne doit pas pouvoir accéder au tableau de bord (la
/// carte, la bascule En ligne) avant cette étape. Voir
/// [ConducteurShellPage], qui affiche cette page à la place du tableau
/// de bord tant que `ProfilConducteur.estValide` est faux.
class ValidationPendingPage extends StatelessWidget {
  const ValidationPendingPage({super.key});

  Future<void> _seDeconnecter(BuildContext context) async {
    await AuthRepository().deconnecter();
    if (context.mounted) context.go(AppRoutes.espacePro);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  color: AppColors.orangeLight,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  color: AppColors.orange,
                  size: 56,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Dossier en cours d\'examen',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                "Votre dossier a bien été reçu. L'équipe du Groupe Santine "
                'procède actuellement à la vérification de vos documents et '
                'de votre véhicule. Cette étape prend généralement 24 à 48h. '
                'Vous recevrez une notification dès que votre compte sera '
                'activé.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.grey, height: 1.6),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.greyLight,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_outlined, size: 16, color: AppColors.grey),
                    SizedBox(width: 8),
                    Text(
                      'Vérification en cours',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.grey),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CentreAidePage()),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  side: const BorderSide(color: AppColors.greyBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Contacter le support',
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _seDeconnecter(context),
                child: const Text(
                  'Se déconnecter',
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
