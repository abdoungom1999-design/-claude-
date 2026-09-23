import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_options.dart';
import '../router/app_routes.dart';
import '../theme/app_colors.dart';
import '../widgets/email_verification_pending_page.dart';
import '../widgets/premium_dialog.dart';

/// Coquille de navigation Client : barre du bas à 4 onglets (Accueil,
/// Activité, Messages, Compte) surmontée d'un bouton d'action flottant
/// central rond ('S') qui déborde légèrement au-dessus de la barre et
/// ouvre le menu d'actions rapides.
class HomeShellPage extends StatelessWidget {
  const HomeShellPage({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _ouvrirMenuActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _MenuActionsRapides(contextParent: context),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (DefaultFirebaseOptions.estConfigure) {
      final utilisateur = FirebaseAuth.instance.currentUser;
      if (utilisateur != null && !utilisateur.emailVerified) {
        return const EmailVerificationPendingPage(
          destinationApresVerification: AppRoutes.home,
        );
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: navigationShell,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(top: 28),
        child: SizedBox(
          width: 64,
          height: 64,
          child: FloatingActionButton(
            onPressed: () => _ouvrirMenuActions(context),
            backgroundColor: AppColors.noirProfond,
            elevation: 4,
            shape: const CircleBorder(),
            child: const Text(
              'S',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppColors.background,
        shape: const CircularNotchedRectangle(),
        notchMargin: 10,
        elevation: 12,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _OngletBarre(
                icon: Icons.home_outlined,
                iconActif: Icons.home_rounded,
                label: 'Accueil',
                selectionne: navigationShell.currentIndex == 0,
                onTap: () => navigationShell.goBranch(0),
              ),
              _OngletBarre(
                icon: Icons.receipt_long_outlined,
                iconActif: Icons.receipt_long_rounded,
                label: 'Activité',
                selectionne: navigationShell.currentIndex == 1,
                onTap: () => navigationShell.goBranch(1),
              ),
              const SizedBox(width: 56),
              _OngletBarre(
                icon: Icons.chat_bubble_outline_rounded,
                iconActif: Icons.chat_bubble_rounded,
                label: 'Messages',
                selectionne: navigationShell.currentIndex == 2,
                onTap: () => navigationShell.goBranch(2),
              ),
              _OngletBarre(
                icon: Icons.person_outline_rounded,
                iconActif: Icons.person_rounded,
                label: 'Compte',
                selectionne: navigationShell.currentIndex == 3,
                onTap: () => navigationShell.goBranch(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OngletBarre extends StatelessWidget {
  const _OngletBarre({
    required this.icon,
    required this.iconActif,
    required this.label,
    required this.selectionne,
    required this.onTap,
  });

  final IconData icon;
  final IconData iconActif;
  final String label;
  final bool selectionne;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final couleur = selectionne ? AppColors.orange : AppColors.grey;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selectionne ? iconActif : icon, color: couleur, size: 24),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: couleur,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuActionsRapides extends StatelessWidget {
  const _MenuActionsRapides({required this.contextParent});

  /// Contexte de la page hôte (stable), utilisé pour les actions qui
  /// s'exécutent après la fermeture de ce bottom sheet — son propre
  /// [BuildContext] ne serait plus fiable une fois le sheet démonté.
  final BuildContext contextParent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.greyBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Que voulez-vous faire ?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          _ActionRapide(
            icon: Icons.two_wheeler_rounded,
            label: 'Course immédiate',
            description: 'Réservez une moto-taxi maintenant',
            onTap: () {
              Navigator.of(context).pop();
              contextParent.push(AppRoutes.clientPassager);
            },
          ),
          _ActionRapide(
            icon: Icons.event_available_outlined,
            label: 'Réservation',
            description: 'Planifiez une course à l\'avance',
            onTap: () => _bientotDisponible(context, 'Réservation'),
          ),
          _ActionRapide(
            icon: Icons.inventory_2_outlined,
            label: 'Livraison',
            description: 'Envoyez un colis rapidement',
            onTap: () {
              Navigator.of(context).pop();
              contextParent.push(AppRoutes.clientColis);
            },
          ),
          _ActionRapide(
            icon: Icons.car_rental_outlined,
            label: 'Location',
            description: 'Louez un véhicule avec chauffeur',
            onTap: () => _bientotDisponible(context, 'Location'),
          ),
          _ActionRapide(
            icon: Icons.flight_takeoff_rounded,
            label: 'Aéroport',
            description: 'Transferts aéroport en toute sérénité',
            onTap: () => _bientotDisponible(context, 'Aéroport'),
          ),
        ],
      ),
    );
  }

  void _bientotDisponible(BuildContext context, String label) {
    Navigator.of(context).pop();
    PremiumDialog.bientotDisponible(contextParent, label);
  }
}

class _ActionRapide extends StatelessWidget {
  const _ActionRapide({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.orangeLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.orange, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 12, color: AppColors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.grey),
          ],
        ),
      ),
    );
  }
}
