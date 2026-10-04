import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/logo_sprint.dart';

class AdminSection {
  const AdminSection({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

const List<AdminSection> adminSections = [
  AdminSection(icon: Icons.dashboard_outlined, label: 'Dashboard'),
  AdminSection(icon: Icons.map_outlined, label: 'Courses en direct'),
  AdminSection(icon: Icons.two_wheeler_outlined, label: 'Chauffeurs'),
  AdminSection(icon: Icons.people_outline_rounded, label: 'Clients'),
  AdminSection(icon: Icons.payments_outlined, label: 'Finances'),
  AdminSection(icon: Icons.support_agent_outlined, label: 'Support'),
  AdminSection(icon: Icons.settings_outlined, label: 'Paramètres'),
];

/// Menu latéral fixe de la Tour de Contrôle : logo Santine, navigation
/// entre les 7 sections, déconnexion en bas.
class AdminSidebar extends StatelessWidget {
  const AdminSidebar({
    super.key,
    required this.indexSelectionne,
    required this.onSelection,
    required this.onDeconnexion,
  });

  final int indexSelectionne;
  final ValueChanged<int> onSelection;
  final VoidCallback onDeconnexion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      decoration: const BoxDecoration(
        color: AppColors.fondBarre,
        border: Border(right: BorderSide(color: AppColors.bordVerre)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: _LogoSantine(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (var i = 0; i < adminSections.length; i++)
                  _ItemMenu(
                    section: adminSections[i],
                    selectionne: i == indexSelectionne,
                    onTap: () => onSelection(i),
                  ),
              ],
            ),
          ),
          const Divider(color: AppColors.bordVerre, height: 1),
          _ItemMenu(
            section: const AdminSection(
              icon: Icons.logout_rounded,
              label: 'Déconnexion',
            ),
            selectionne: false,
            onTap: onDeconnexion,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _LogoSantine extends StatelessWidget {
  const _LogoSantine();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        LogoSprint(taille: 38),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sprint',
              style: TextStyle(
                color: AppColors.onyx,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Groupe Santine',
              style: TextStyle(color: AppColors.texteDiscret, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({
    required this.section,
    required this.selectionne,
    required this.onTap,
  });

  final AdminSection section;
  final bool selectionne;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            // Onglet actif : pastille bleue, icône et texte blancs.
            decoration: BoxDecoration(
              color: selectionne ? AppColors.bleu : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  section.icon,
                  size: 19,
                  color: selectionne ? Colors.white : AppColors.onyx,
                ),
                const SizedBox(width: 12),
                Text(
                  section.label,
                  style: TextStyle(
                    color: selectionne ? Colors.white : AppColors.onyx,
                    fontSize: 13.5,
                    fontWeight: selectionne ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
