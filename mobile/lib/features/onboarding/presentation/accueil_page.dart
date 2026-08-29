import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';

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
              const Text(
                'Sprint',
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Que souhaitez-vous faire ?'),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go(AppRoutes.clientPassager),
                  child: const Text('Passager'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go(AppRoutes.clientColis),
                  child: const Text('Livraison Colis'),
                ),
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () => context.go(AppRoutes.espacePro),
                child: const Text('Espace conducteur / admin'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
