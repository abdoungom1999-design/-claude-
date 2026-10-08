import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../../features/messages/presentation/widgets/pastille_non_lus.dart';

/// Barre de navigation du bas, charte « Onyx & Vert » : fond Onyx, liseré fin
/// en haut, onglet actif en vert dans une pastille teintée, onglets inactifs
/// en gris clair (7,9:1). Sert au Client (avec encoche pour le bouton
/// central) et au Chauffeur.
class BarreNavigation extends StatelessWidget {
  const BarreNavigation({super.key, required this.onglets, this.avecEncoche = false});

  final List<Widget> onglets;

  /// Encoche arrondie pour un bouton d'action flottant posé au centre.
  final bool avecEncoche;

  @override
  Widget build(BuildContext context) {
    final rangee = SizedBox(
      height: 64,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: onglets),
    );
    return BottomAppBar(
      color: AppColors.fondBarre,
      surfaceTintColor: Colors.transparent,
      shadowColor: AppColors.shadow,
      shape: avecEncoche ? const CircularNotchedRectangle() : null,
      notchMargin: 10,
      elevation: avecEncoche ? 8 : 0,
      padding: EdgeInsets.zero,
      child: avecEncoche
          ? rangee
          : DecoratedBox(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.bordVerre))),
              child: rangee,
            ),
    );
  }
}

/// Un onglet de [BarreNavigation] : pictogramme et libellé, en vert et dans
/// une pastille quand il est sélectionné ; [nonLus] pose la pastille rouge
/// des messages non lus sur le pictogramme.
class OngletBarre extends StatelessWidget {
  const OngletBarre({
    super.key,
    required this.icon,
    required this.iconActif,
    required this.label,
    required this.selectionne,
    required this.onTap,
    this.nonLus = 0,
  });

  final IconData icon;
  final IconData iconActif;
  final String label;
  final bool selectionne;
  final VoidCallback onTap;
  final int nonLus;

  @override
  Widget build(BuildContext context) {
    final couleur = selectionne ? AppColors.vert : AppColors.texteDiscret;
    return Semantics(
      button: true,
      selected: selectionne,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 52,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selectionne ? AppColors.vert.withValues(alpha: 0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: PastilleNonLus(
                  nombre: nonLus,
                  child: Icon(selectionne ? iconActif : icon, color: couleur, size: 24),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 10.5, fontWeight: selectionne ? FontWeight.w800 : FontWeight.w600, color: couleur),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
