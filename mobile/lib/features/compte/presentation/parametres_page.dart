import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/section_list_tile.dart';
import '../../auth/data/auth_repository.dart';
import 'aide_support_page.dart';
import 'conditions_utilisation_page.dart';
import 'notifications_page.dart';
import 'politique_confidentialite_page.dart';
import 'preferences_page.dart';

/// Menu Paramètres : notifications, préférences, informations légales,
/// support et suppression de compte.
class ParametresPage extends StatelessWidget {
  const ParametresPage({super.key});

  void _ouvrir(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _afficherInfoApplication(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sprint'),
        content: const Text(
          'Version 1.4.0\nGroupe Santine — Dakar, Sénégal\n\n'
          'Application de VTC moto-taxi et de livraison de colis.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmerSuppression(BuildContext context) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Supprimer votre compte ?'),
        content: const Text(
          'Cette action est irréversible. Toutes vos données (historique, '
          'favoris, portefeuille) seront définitivement supprimées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Supprimer',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;

    await AuthRepository().deconnecter();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Votre compte a été supprimé.')),
    );
    context.go(AppRoutes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SectionListTile(
              icon: Icons.notifications_outlined,
              label: 'Notifications',
              onTap: () => _ouvrir(context, const NotificationsPage()),
            ),
            SectionListTile(
              icon: Icons.tune_rounded,
              label: 'Préférences',
              onTap: () => _ouvrir(context, const PreferencesPage()),
            ),
            SectionListTile(
              icon: Icons.smartphone_rounded,
              label: 'Application (Version 1.4.0)',
              onTap: () => _afficherInfoApplication(context),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 6),
              child: Text(
                'Légal & support',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.grey),
              ),
            ),
            SectionListTile(
              icon: Icons.description_outlined,
              label: 'CGU',
              onTap: () => _ouvrir(context, const ConditionsUtilisationPage()),
            ),
            SectionListTile(
              icon: Icons.privacy_tip_outlined,
              label: 'Politique de confidentialité',
              onTap: () => _ouvrir(context, const PolitiqueConfidentialitePage()),
            ),
            SectionListTile(
              icon: Icons.support_agent_outlined,
              label: 'Support',
              onTap: () => _ouvrir(context, const AideSupportPage()),
            ),
            const SizedBox(height: 28),
            InkWell(
              onTap: () => _confirmerSuppression(context),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 19),
                    SizedBox(width: 8),
                    Text(
                      'Supprimer mon compte',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
