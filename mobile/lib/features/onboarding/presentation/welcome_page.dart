import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';

/// Écran d'accueil pré-authentification : héros premium en noir profond,
/// slogan, et les trois entrées de connexion empilées. Aucune photo de
/// véhicule n'est utilisée (pas de banque d'images de marque disponible
/// dans cet environnement) : un pictogramme de véhicule sur fond dégradé
/// tient lieu de visuel héros, dans le même esprit premium.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  void _bientotDisponible(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label : bientôt disponible')),
    );
  }

  Future<void> _seConnecter(BuildContext context) async {
    final connecte = await context.push<bool>(AppRoutes.clientLogin);
    if (connecte == true && context.mounted) {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.noirProfond,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.orange, AppColors.orangeDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.orange.withValues(alpha: 0.35),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.directions_car_filled_rounded,
                  color: Colors.white,
                  size: 64,
                ),
              ),
              const SizedBox(height: 36),
              const Text(
                'Sprint',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Votre chauffeur en quelques secondes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                ),
              ),
              const Spacer(flex: 2),
              _BoutonAuth(
                label: 'Continuer avec mon numéro',
                orange: true,
                onPressed: () => _seConnecter(context),
              ),
              const SizedBox(height: 12),
              _BoutonAuth(
                label: 'Continuer avec mon email',
                orange: false,
                onPressed: () => _seConnecter(context),
              ),
              const SizedBox(height: 12),
              _BoutonAuth(
                label: 'Continuer avec Apple',
                orange: false,
                icon: Icons.apple,
                onPressed: () => _bientotDisponible(context, 'Connexion Apple'),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => context.push(AppRoutes.espacePro),
                child: Text(
                  'Espace conducteur / admin',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoutonAuth extends StatelessWidget {
  const _BoutonAuth({
    required this.label,
    required this.orange,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final bool orange;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: orange ? AppColors.orange : Colors.white,
          foregroundColor: orange ? Colors.white : AppColors.text,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
