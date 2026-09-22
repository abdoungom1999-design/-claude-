import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';

/// Écran d'accueil : choix binaire strict entre "Passager" et
/// "Livraison Colis", point d'entrée des deux flux client distincts.
class AccueilPage extends StatelessWidget {
  const AccueilPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: AppColors.background,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Sprint',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Que souhaitez-vous faire ?',
                style: TextStyle(fontSize: 15, color: AppColors.grey),
              ),
              const SizedBox(height: 48),
              PrimaryButton(
                label: 'Passager',
                icon: Icons.two_wheeler_rounded,
                onPressed: () => context.push(AppRoutes.clientPassager),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Livraison Colis',
                icon: Icons.inventory_2_outlined,
                onPressed: () => context.push(AppRoutes.clientColis),
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () => context.push(AppRoutes.espacePro),
                child: const Text(
                  'Espace conducteur / admin',
                  style: TextStyle(color: AppColors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
