import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/onyx_vert.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';

/// Écran d'accueil pré-authentification, en charte « Onyx & Vert » : fond
/// Onyx à halos verts, logo (tuile Onyx, « S » blanc et liseré vert) sur une
/// lueur verte, slogan, et les trois entrées de connexion dans une carte
/// « verre ». Pas de photo. Les actions et leurs
/// libellés sont ceux de l'ancienne version.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  Future<void> _seConnecter(BuildContext context) async {
    final connecte = await context.push<bool>(AppRoutes.clientLogin);
    if (connecte == true && context.mounted) {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemeOnyxVert(
      child: Scaffold(
        backgroundColor: AppColors.fond,
        body: FondOnyxVert(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: TuileLogo(taille: 92)),
                      const SizedBox(height: 26),
                      const Text(
                        'Sprint',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.texte,
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Votre chauffeur en quelques secondes',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.texteDiscret, fontSize: 16, height: 1.3),
                      ),
                      const SizedBox(height: 34),
                      CarteVerre(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _BoutonAuth(
                              label: 'Continuer avec mon numéro',
                              principal: true,
                              onPressed: () => _seConnecter(context),
                            ),
                            const SizedBox(height: 10),
                            _BoutonAuth(
                              label: 'Continuer avec mon email',
                              principal: false,
                              onPressed: () => _seConnecter(context),
                            ),
                            const SizedBox(height: 10),
                            _BoutonAuth(
                              label: 'Continuer avec Apple',
                              principal: false,
                              icon: Icons.apple,
                              onPressed: () => PremiumDialog.bientotDisponible(context, 'Connexion Apple'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: () => context.push(AppRoutes.espacePro),
                        child: const Text(
                          'Espace conducteur / admin',
                          style: TextStyle(color: AppColors.texteDiscret, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton d'entrée : bouton d'action vert (dégradé, texte Onyx : la touche
/// Sprint qui guide l'utilisateur) ou verre sombre à bord fin.
class _BoutonAuth extends StatelessWidget {
  const _BoutonAuth({
    required this.label,
    required this.principal,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final bool principal;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (principal) return PrimaryButton(label: label, icon: icon, onPressed: onPressed);
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.verre,
          foregroundColor: AppColors.texte,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.bordVerre),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 21),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
