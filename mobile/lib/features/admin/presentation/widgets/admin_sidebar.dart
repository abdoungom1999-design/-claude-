import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

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
      color: AppColors.noirProfond,
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
          const Divider(color: Colors.white12, height: 1),
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
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.orange,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sprint',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Groupe Santine',
              style: TextStyle(color: Colors.white54, fontSize: 11),
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
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selectionne
                  ? AppColors.orange.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(
                  color: selectionne ? AppColors.orange : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  section.icon,
                  size: 19,
                  color: selectionne ? AppColors.orange : Colors.white70,
                ),
                const SizedBox(width: 12),
                Text(
                  section.label,
                  style: TextStyle(
                    color: selectionne ? Colors.white : Colors.white70,
                    fontSize: 13.5,
                    fontWeight: selectionne ? FontWeight.w600 : FontWeight.w500,
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
