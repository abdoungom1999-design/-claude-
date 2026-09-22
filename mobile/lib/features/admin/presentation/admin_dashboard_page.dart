import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/data/auth_repository.dart';
import 'sections/admin_chauffeurs_section.dart';
import 'sections/admin_clients_section.dart';
import 'sections/admin_courses_direct_section.dart';
import 'sections/admin_finances_section.dart';
import 'sections/admin_overview_section.dart';
import 'sections/admin_parametres_section.dart';
import 'sections/admin_support_section.dart';
import 'widgets/admin_sidebar.dart';
import 'widgets/admin_topbar.dart';

/// Tour de Contrôle du Groupe Santine : tableau de bord Administrateur,
/// pensé pour un affichage Desktop (`/admin`). Entièrement piloté par des
/// données factices (voir [AdminDemoData] et [DemoData]/[AdminRepository]
/// pour la page Chauffeurs), pour naviguer sans backend.
class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  int _indexSelectionne = 0;
  final _authRepository = AuthRepository();

  static const _sections = <Widget>[
    AdminOverviewSection(),
    AdminCoursesDirectSection(),
    AdminChauffeursSection(),
    AdminClientsSection(),
    AdminFinancesSection(),
    AdminSupportSection(),
    AdminParametresSection(),
  ];

  Future<void> _seDeconnecter() async {
    await _authRepository.deconnecter();
    if (mounted) context.go(AppRoutes.espacePro);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.greyLight,
      body: Row(
        children: [
          AdminSidebar(
            indexSelectionne: _indexSelectionne,
            onSelection: (index) => setState(() => _indexSelectionne = index),
            onDeconnexion: _seDeconnecter,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminTopbar(
                  titreSection: adminSections[_indexSelectionne].label,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1400),
                      child: IndexedStack(
                        index: _indexSelectionne,
                        children: _sections,
                      ),
                    ),
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
