import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/section_list_tile.dart';
import 'conditions_utilisation_page.dart';
import 'politique_confidentialite_page.dart';

/// À propos de Sprint (Groupe Santine).
class AProposPage extends StatelessWidget {
  const AProposPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('À propos de Sprint')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.orange, AppColors.orangeDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 40),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Sprint',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Version 1.4.0',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.grey),
            ),
            const SizedBox(height: 20),
            const Text(
              'Sprint est l\'application de VTC moto-taxi et de livraison de '
              'colis de Groupe Santine, conçue pour connecter rapidement et '
              'en toute sécurité les habitants de Dakar à des chauffeurs '
              'partenaires vérifiés.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.grey, height: 1.5),
            ),
            const SizedBox(height: 28),
            SectionListTile(
              icon: Icons.description_outlined,
              label: 'Conditions d\'utilisation',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConditionsUtilisationPage()),
              ),
            ),
            SectionListTile(
              icon: Icons.privacy_tip_outlined,
              label: 'Politique de confidentialité',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PolitiqueConfidentialitePage()),
              ),
            ),
            const SizedBox(height: 24),
            const Center(
              child: Text(
                '© 2026 Groupe Santine. Tous droits réservés.',
                style: TextStyle(fontSize: 11, color: AppColors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
