import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/banner_carousel.dart';
import '../../../core/widgets/reassurance_tile.dart';
import '../../../core/widgets/trip_map.dart';

/// Onglet Accueil : recherche de destination, carte, bannières
/// promotionnelles et grille de réassurance.
class HomeTabPage extends StatelessWidget {
  const HomeTabPage({super.key});

  static const _positionActuelle = LatLng(14.6928, -17.4467);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Sprint',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _IconeHeader(
                      icon: Icons.notifications_outlined,
                      onTap: () {},
                    ),
                    const SizedBox(width: 10),
                    _IconeHeader(
                      icon: Icons.person_outline_rounded,
                      onTap: () => context.go(AppRoutes.compteTab),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            _CarteRecherche(
              onTap: () => context.push(AppRoutes.clientPassager),
            ),
            const SizedBox(height: 20),
            const TripMap(depart: _positionActuelle, height: 190),
            const SizedBox(height: 24),
            const BannerCarousel(),
            const SizedBox(height: 24),
            const Text(
              'Pourquoi Sprint',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const _GrilleReassurance(),
          ],
        ),
      ),
    );
  }
}

class _IconeHeader extends StatelessWidget {
  const _IconeHeader({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: AppColors.greyLight,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 19, color: AppColors.text),
      ),
    );
  }
}

class _CarteRecherche extends StatelessWidget {
  const _CarteRecherche({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.orange, AppColors.orangeDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.orange.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Où allez-vous ?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, color: AppColors.grey, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ajouter une destination',
                      style: TextStyle(color: AppColors.grey, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.schedule, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Maintenant',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GrilleReassurance extends StatelessWidget {
  const _GrilleReassurance();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: ReassuranceTile(
            icon: Icons.shield_outlined,
            label: 'Sécurité',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: ReassuranceTile(
            icon: Icons.verified_user_outlined,
            label: 'Chauffeurs\nvérifiés',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: ReassuranceTile(
            icon: Icons.payments_outlined,
            label: 'Paiement\nsimple',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: ReassuranceTile(
            icon: Icons.support_agent_outlined,
            label: 'Support\n24/7',
          ),
        ),
      ],
    );
  }
}
