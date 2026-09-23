import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Salle d'attente obligatoire du chauffeur dont le dossier KYC a été
/// soumis (voir [ConducteurKYCPage]) mais pas encore validé par un
/// administrateur (`statutValidation == 'en_attente'` dans le document
/// Firestore de l'utilisateur, voir le "Gardien" dans
/// [ConducteurShellPage]). Volontairement minimaliste et sans aucune
/// navigation (pas de barre du bas, pas de menu) : tant que le compte
/// n'est pas validé, il n'y a rien d'autre à faire ici qu'attendre.
class ConducteurEnAttentePage extends StatelessWidget {
  const ConducteurEnAttentePage({super.key, required this.onDeconnexion});

  final VoidCallback onDeconnexion;

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
              const _LogoSprint(),
              const SizedBox(height: 40),
              const _IllustrationExamenDossier(),
              const SizedBox(height: 36),
              const Text(
                'Dossier en cours de vérification',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Vos documents sont en cours d\'examen par l\'équipe du Groupe '
                'Santine. Vous serez notifié dès la validation de votre compte.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.grey, height: 1.6),
              ),
              const Spacer(),
              TextButton(
                onPressed: onDeconnexion,
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

class _LogoSprint extends StatelessWidget {
  const _LogoSprint();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.orange, AppColors.orangeDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        const Text(
          'Sprint',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.text),
        ),
      ],
    );
  }
}

/// Illustration composée uniquement de formes et icônes Flutter
/// (cercles concentriques + icônes), sans image réseau — l'accès aux
/// CDN d'images est bloqué depuis ce bac à sable (même constat que sur
/// l'écran Welcome et le bandeau d'authentification).
class _IllustrationExamenDossier extends StatelessWidget {
  const _IllustrationExamenDossier();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.orangeLight.withValues(alpha: 0.55),
            ),
          ),
          Container(
            width: 130,
            height: 130,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.orangeLight,
            ),
          ),
          const Icon(Icons.fact_check_rounded, color: AppColors.orange, size: 60),
          Positioned(
            bottom: 16,
            right: 22,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.orange,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Icon(Icons.hourglass_top_rounded, color: Colors.white, size: 19),
            ),
          ),
        ],
      ),
    );
  }
}
