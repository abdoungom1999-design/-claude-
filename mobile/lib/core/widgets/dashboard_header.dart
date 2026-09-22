import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Bandeau dégradé orange à coins arrondis pour les tableaux de bord
/// internes (Admin, Conducteur) : même identité visuelle que
/// [AuthScaffold] côté écrans d'authentification, adaptée à une page qui
/// enchaîne ensuite sur une liste/scroll plutôt qu'une carte flottante
/// unique.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onDeconnexion,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onDeconnexion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.orange, AppColors.orangeDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            top: -40,
            right: -20,
            child: _Cercle(taille: 130, opacite: 0.10),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (onDeconnexion != null)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: onDeconnexion,
                    icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                    tooltip: 'Se déconnecter',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Cercle extends StatelessWidget {
  const _Cercle({required this.taille, required this.opacite});

  final double taille;
  final double opacite;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacite),
      ),
    );
  }
}
