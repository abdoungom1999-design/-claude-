import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/onyx_light.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';

/// Sélecteur temporaire entre l'interface Conducteur et l'interface Admin.
/// Sera remplacé par un flux d'authentification par rôle.
class EspaceProPage extends StatelessWidget {
  const EspaceProPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemeOnyxLight(
      child: Scaffold(
        backgroundColor: AppColors.fondClair,
        appBar: AppBar(
          title: const Text('Espace professionnel'),
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        extendBodyBehindAppBar: true,
        body: FondOnyxLight(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CarteVerre(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PrimaryButton(
                          label: 'Conducteur',
                          icon: Icons.two_wheeler_rounded,
                          onPressed: () => context.push(AppRoutes.conducteurLogin),
                        ),
                        const SizedBox(height: 12),
                        SecondaryButton(
                          label: 'Admin',
                          icon: Icons.admin_panel_settings_outlined,
                          onPressed: () => context.push(AppRoutes.adminLogin),
                        ),
                      ],
                    ),
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
