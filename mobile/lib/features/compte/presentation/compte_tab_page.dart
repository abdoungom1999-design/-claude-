import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/coming_soon_view.dart';
import '../../../core/widgets/section_list_tile.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../../core/widgets/wallet_card.dart';
import '../../auth/data/auth_repository.dart';

/// Onglet Compte : profil, portefeuille, statistiques et menu de
/// paramètres.
class CompteTabPage extends StatefulWidget {
  const CompteTabPage({super.key});

  @override
  State<CompteTabPage> createState() => _CompteTabPageState();
}

class _CompteTabPageState extends State<CompteTabPage> {
  final _authRepository = AuthRepository();
  bool _payerAvecSolde = false;

  void _ouvrirPage(BuildContext context, String titre, IconData icon) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(titre)),
          body: ComingSoonView(icon: icon, titre: titre),
        ),
      ),
    );
  }

  Future<void> _seDeconnecter() async {
    await _authRepository.deconnecter();
    if (mounted) context.go(AppRoutes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.orange, AppColors.orangeDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'V',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DemoData.monNomClient,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Client Sprint',
                        style: TextStyle(fontSize: 12.5, color: AppColors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            WalletCard(
              soldeFcfa: DemoData.soldePortefeuilleFcfa,
              payerAvecSolde: _payerAvecSolde,
              onTogglePaiement: (valeur) =>
                  setState(() => _payerAvecSolde = valeur),
              onRecharger: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Recharge du portefeuille : bientôt disponible'),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Note moyenne',
                    valeur: '${DemoData.noteMoyenneClient}',
                    icon: Icons.star_rounded,
                    accent: Colors.amber.shade700,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: StatTile(
                    label: 'Courses',
                    valeur: '${DemoData.coursesEffectueesClient}',
                    icon: Icons.route_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: StatTile(
                    label: 'Réservations',
                    valeur: '${DemoData.reservationsClient}',
                    icon: Icons.event_available_outlined,
                    accent: Colors.blueGrey,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Favoris',
                    valeur: '${DemoData.favorisClient}',
                    icon: Icons.favorite_border_rounded,
                    accent: Colors.pink.shade400,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const Text(
              'Paramètres',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            SectionListTile(
              icon: Icons.badge_outlined,
              label: 'Informations personnelles',
              onTap: () => _ouvrirPage(
                context,
                'Informations personnelles',
                Icons.badge_outlined,
              ),
            ),
            SectionListTile(
              icon: Icons.shield_outlined,
              label: 'Sécurité',
              onTap: () => _ouvrirPage(context, 'Sécurité', Icons.shield_outlined),
            ),
            SectionListTile(
              icon: Icons.favorite_border_rounded,
              label: 'Favoris',
              onTap: () =>
                  _ouvrirPage(context, 'Favoris', Icons.favorite_border_rounded),
            ),
            SectionListTile(
              icon: Icons.star_border_rounded,
              label: 'Courses à noter',
              onTap: () => _ouvrirPage(
                context,
                'Courses à noter',
                Icons.star_border_rounded,
              ),
            ),
            SectionListTile(
              icon: Icons.person_add_alt_outlined,
              label: 'Inviter des amis',
              onTap: () => _ouvrirPage(
                context,
                'Inviter des amis',
                Icons.person_add_alt_outlined,
              ),
            ),
            SectionListTile(
              icon: Icons.help_outline_rounded,
              label: 'Aide & Support',
              onTap: () => _ouvrirPage(
                context,
                'Aide & Support',
                Icons.help_outline_rounded,
              ),
            ),
            const SizedBox(height: 8),
            SectionListTile(
              icon: Icons.logout_rounded,
              label: 'Se déconnecter',
              onTap: _seDeconnecter,
            ),
          ],
        ),
      ),
    );
  }
}
