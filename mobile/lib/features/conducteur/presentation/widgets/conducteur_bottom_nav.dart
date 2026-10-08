import 'package:flutter/material.dart';
import '../../../../core/widgets/barre_navigation.dart';

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
    // Onyx & Vert : fond Onyx, icônes grises, onglet actif vert.
    return BarreNavigation(
      onglets: [
        for (var i = 0; i < _onglets.length; i++)
          OngletBarre(
            icon: _onglets[i].icon,
            iconActif: _onglets[i].iconActif,
            label: _onglets[i].label,
            selectionne: indexSelectionne == i,
            onTap: () => onSelection(i),
          ),
      ],
    );
  }
}
