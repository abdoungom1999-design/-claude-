import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';

/// Sélecteur temporaire entre l'interface Conducteur et l'interface Admin.
/// Sera remplacé par un flux d'authentification par rôle.
class EspaceProPage extends StatelessWidget {
  const EspaceProPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Espace professionnel')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.go(AppRoutes.conducteur),
                child: const Text('Conducteur'),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.go(AppRoutes.admin),
                child: const Text('Admin'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
