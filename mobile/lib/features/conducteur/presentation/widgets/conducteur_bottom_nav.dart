import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Barre de navigation basse de l'espace Conducteur : Accueil, Messages,
/// Gains, Évaluations, Compte.
class ConducteurBottomNav extends StatelessWidget {
  const ConducteurBottomNav({
    super.key,
    required this.indexSelectionne,
    required this.onSelection,
  });

  final int indexSelectionne;
  final ValueChanged<int> onSelection;

  static const _onglets = [
    (icon: Icons.home_outlined, iconActif: Icons.home_rounded, label: 'Accueil'),
    (icon: Icons.chat_bubble_outline_rounded, iconActif: Icons.chat_bubble_rounded, label: 'Messages'),
    (icon: Icons.payments_outlined, iconActif: Icons.payments_rounded, label: 'Gains'),
    (icon: Icons.star_border_rounded, iconActif: Icons.star_rounded, label: 'Évaluations'),
    (icon: Icons.person_outline_rounded, iconActif: Icons.person_rounded, label: 'Compte'),
  ];

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: AppColors.background,
      elevation: 12,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 64,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < _onglets.length; i++)
              _OngletBarre(
                icon: _onglets[i].icon,
                iconActif: _onglets[i].iconActif,
                label: _onglets[i].label,
                selectionne: indexSelectionne == i,
                onTap: () => onSelection(i),
              ),
          ],
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
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: couleur),
            ),
          ],
        ),
      ),
    );
  }
}
