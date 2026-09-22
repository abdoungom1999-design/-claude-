import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/banner_carousel.dart';
import '../../../core/widgets/premium_dialog.dart';
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
            const SizedBox(height: 32),
            const Text(
              'Découvrez nos univers',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Toutes les façons de vivre Sprint au quotidien.',
              style: TextStyle(fontSize: 12.5, color: AppColors.grey),
            ),
            const SizedBox(height: 14),
            _CarteUnivers(
              titre: 'Sprint Express',
              sousTitre: 'La livraison moto la plus rapide de Dakar',
              imageUrl:
                  'https://images.unsplash.com/photo-1558981806-ec527fa84c39'
                  '?auto=format&fit=crop&w=1200&q=80',
              onTap: () => context.push(AppRoutes.clientColis),
            ),
            const SizedBox(height: 14),
            _CarteUnivers(
              titre: 'Sprint Food',
              sousTitre: 'Vos plats préférés, livrés chauds',
              imageUrl:
                  'https://images.unsplash.com/photo-1546069901-ba9599a7e63c'
                  '?auto=format&fit=crop&w=1200&q=80',
              onTap: () => PremiumDialog.bientotDisponible(context, 'Sprint Food'),
            ),
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

/// Grande carte verticale plein cadre (photo + filtre sombre + titre) de
/// la section "Découvrez nos univers". Repli en dégradé noir si la photo
/// ne charge pas (voir note de transparence en tête de [BannerCarousel]
/// pour les mêmes réserves sur les URLs Unsplash utilisées ici).
class _CarteUnivers extends StatelessWidget {
  const _CarteUnivers({
    required this.titre,
    required this.sousTitre,
    required this.imageUrl,
    required this.onTap,
  });

  final String titre;
  final String sousTitre;
  final String imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 190,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const _RepliCarteUnivers();
                },
                errorBuilder: (context, error, stackTrace) =>
                    const _RepliCarteUnivers(),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.75),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.3, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 10)],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sousTitre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_outward_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepliCarteUnivers extends StatelessWidget {
  const _RepliCarteUnivers();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.noirProfondClair, AppColors.noirProfond],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}
