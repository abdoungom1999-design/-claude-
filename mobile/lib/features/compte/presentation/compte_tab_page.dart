import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_list_tile.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../../core/widgets/wallet_card.dart';
import '../../auth/data/auth_repository.dart';
import 'aide_support_page.dart';
import 'conditions_utilisation_page.dart';
import 'courses_a_noter_page.dart';
import 'favoris_page.dart';
import 'informations_personnelles_page.dart';
import 'inviter_amis_page.dart';
import 'parametres_page.dart';
import 'politique_confidentialite_page.dart';
import 'securite_page.dart';

const _montantsRecharge = [1000, 2000, 5000, 10000, 20000];

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

  void _ouvrir(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _recharger() async {
    final montant = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _RechargeSheet(),
    );
    if (montant == null || !mounted) return;

    setState(() => DemoData.rechargerPortefeuille(montant));
    if (!mounted) return;
    PremiumDialog.afficher(
      context,
      icon: Icons.account_balance_wallet_outlined,
      titre: 'Portefeuille rechargé',
      message: 'Votre solde a été crédité de $montant FCFA.',
      succes: true,
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
            StreamBuilder<Map<String, dynamic>?>(
              stream: _authRepository.profilUtilisateurStream(),
              builder: (context, snapshot) {
                final nomFirestore = (snapshot.data?['nom'] as String?)?.trim();
                final nomAffiche = (nomFirestore != null && nomFirestore.isNotEmpty)
                    ? nomFirestore
                    : DemoData.monNomClient;
                final initiale = nomAffiche.isNotEmpty ? nomAffiche[0].toUpperCase() : '?';
                return Row(
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
                      child: Text(
                        initiale,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nomAffiche,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Client Sprint',
                            style: TextStyle(fontSize: 12.5, color: AppColors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),
            WalletCard(
              soldeFcfa: DemoData.soldePortefeuilleFcfa,
              payerAvecSolde: _payerAvecSolde,
              onTogglePaiement: (valeur) =>
                  setState(() => _payerAvecSolde = valeur),
              onRecharger: _recharger,
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
              'Compte',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            SectionListTile(
              icon: Icons.badge_outlined,
              label: 'Informations personnelles',
              onTap: () => _ouvrir(const InformationsPersonnellesPage()),
            ),
            SectionListTile(
              icon: Icons.shield_outlined,
              label: 'Sécurité',
              onTap: () => _ouvrir(const SecuritePage()),
            ),
            SectionListTile(
              icon: Icons.favorite_border_rounded,
              label: 'Favoris',
              onTap: () => _ouvrir(const FavorisPage()),
            ),
            SectionListTile(
              icon: Icons.star_border_rounded,
              label: 'Courses à noter',
              onTap: () => _ouvrir(const CoursesANoterPage()),
            ),
            SectionListTile(
              icon: Icons.person_add_alt_outlined,
              label: 'Inviter des amis',
              onTap: () => _ouvrir(const InviterAmisPage()),
            ),
            SectionListTile(
              icon: Icons.help_outline_rounded,
              label: 'Aide & Support',
              onTap: () => _ouvrir(const AideSupportPage()),
            ),
            SectionListTile(
              icon: Icons.settings_outlined,
              label: 'Paramètres',
              onTap: () => _ouvrir(const ParametresPage()),
            ),
            const SizedBox(height: 20),
            const Text(
              'Informations légales',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            SectionListTile(
              icon: Icons.description_outlined,
              label: 'Conditions d\'utilisation',
              onTap: () => _ouvrir(const ConditionsUtilisationPage()),
            ),
            SectionListTile(
              icon: Icons.privacy_tip_outlined,
              label: 'Politique de confidentialité',
              onTap: () => _ouvrir(const PolitiqueConfidentialitePage()),
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

class _RechargeSheet extends StatefulWidget {
  const _RechargeSheet();

  @override
  State<_RechargeSheet> createState() => _RechargeSheetState();
}

class _RechargeSheetState extends State<_RechargeSheet> {
  int _montantChoisi = _montantsRecharge[1];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.greyBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Recharger mon portefeuille',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _montantsRecharge.map((montant) {
              final selectionne = montant == _montantChoisi;
              return ChoiceChip(
                label: Text('$montant FCFA'),
                selected: selectionne,
                onSelected: (_) => setState(() => _montantChoisi = montant),
                selectedColor: AppColors.orange,
                labelStyle: TextStyle(
                  color: selectionne ? Colors.white : AppColors.text,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: AppColors.greyLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide.none,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Confirmer la recharge',
            onPressed: () => Navigator.of(context).pop(_montantChoisi),
          ),
        ],
      ),
    );
  }
}
