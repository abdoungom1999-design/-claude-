import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/premium_dialog.dart';
import '../../../compte/presentation/centre_aide_page.dart';
import '../../../messages/presentation/messages_tab_page.dart';
import '../../data/conducteur_repository.dart';

/// Onglet Compte : identité du conducteur, véhicule, statut des
/// documents (Permis, Assurance, Carte grise) et accès aux pages
/// annexes (Messages, Centre d'aide, Paramètres, déconnexion).
class ConducteurCompteTab extends StatelessWidget {
  const ConducteurCompteTab({
    super.key,
    required this.profil,
    required this.onDeconnexion,
  });

  final ProfilConducteur? profil;
  final VoidCallback onDeconnexion;

  void _ouvrirPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final nom = profil?.nom ?? 'Conducteur';
    final documentsValides = profil?.estValide ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Compte',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.orange, AppColors.orangeDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(nom, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    profil?.telephone ?? '',
                    style: const TextStyle(fontSize: 13, color: AppColors.grey),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.greyLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.two_wheeler_rounded, color: AppColors.text, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            [
                              profil?.vehiculeId,
                              profil?.plaqueImmatriculation,
                            ].where((v) => v != null && v.isNotEmpty).join(' - '),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Documents',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _LigneDocument(
                    icon: Icons.badge_outlined,
                    label: 'Permis de conduire',
                    valide: documentsValides,
                  ),
                  const Divider(height: 1, color: AppColors.greyBorder),
                  _LigneDocument(
                    icon: Icons.shield_outlined,
                    label: 'Assurance véhicule',
                    valide: documentsValides,
                  ),
                  const Divider(height: 1, color: AppColors.greyBorder),
                  _LigneDocument(
                    icon: Icons.description_outlined,
                    label: 'Carte grise',
                    valide: documentsValides,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Plus',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _ItemMenu(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Messages',
                    badge: '2',
                    onTap: () => _ouvrirPage(context, const MessagesTabPage()),
                  ),
                  const Divider(height: 1, color: AppColors.greyBorder),
                  _ItemMenu(
                    icon: Icons.help_outline_rounded,
                    label: 'Centre d\'aide',
                    onTap: () => _ouvrirPage(context, const CentreAidePage()),
                  ),
                  const Divider(height: 1, color: AppColors.greyBorder),
                  _ItemMenu(
                    icon: Icons.settings_outlined,
                    label: 'Paramètres',
                    onTap: () => PremiumDialog.bientotDisponible(context, 'Paramètres'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            AppCard(
              onTap: onDeconnexion,
              child: const Row(
                children: [
                  Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'Se déconnecter',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LigneDocument extends StatelessWidget {
  const _LigneDocument({
    required this.icon,
    required this.label,
    required this.valide,
  });

  final IconData icon;
  final String label;
  final bool valide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.text),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (valide ? AppColors.vert : AppColors.orange).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  valide ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                  size: 13,
                  color: valide ? AppColors.vert : AppColors.orange,
                ),
                const SizedBox(width: 5),
                Text(
                  valide ? 'Validé' : 'En attente',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: valide ? AppColors.vert : AppColors.orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.text, size: 21),
      title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      trailing: badge != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge!,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            )
          : const Icon(Icons.chevron_right_rounded, color: AppColors.grey),
      onTap: onTap,
    );
  }
}
