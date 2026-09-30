import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/racine_de_session.dart';
import '../../../firebase_options.dart';
import '../../auth/data/auth_repository.dart';
import '../data/admin_kyc_service.dart';
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
/// pensé pour un affichage Desktop (`/admin`). En Firebase réel, chaque
/// page ne montre que des données Firestore ; sans Firebase, les données
/// de démonstration ([AdminDemoData]) permettent de naviguer.
class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  int _indexSelectionne = 0;
  final _authRepository = AuthRepository();

  /// Le rattrapage des profils publics ne tourne qu'une fois par session.
  static bool _profilsSynchronises = false;

  @override
  void initState() {
    super.initState();
    if (DefaultFirebaseOptions.estConfigure && !_profilsSynchronises) {
      _profilsSynchronises = true;
      AdminKycService().synchroniserProfilsPublics().then(
            (n) => debugPrint('Profils publics synchronisés : $n comptes.'),
            onError: (Object e) => debugPrint('Synchronisation des profils publics impossible : $e'),
          );
    }
  }

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
    // Racine de l'espace Admin : le geste « retour » ne mène jamais à la
    // connexion ; depuis une autre section, il revient d'abord à la première.
    return RacineDeSession(
      surRetour: () {
        if (_indexSelectionne == 0) return false;
        setState(() => _indexSelectionne = 0);
        return true;
      },
      child: _tableauDeBord(),
    );
  }

  Widget _tableauDeBord() {
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
                  compteAdmin: DefaultFirebaseOptions.estConfigure
                      ? FirebaseAuth.instance.currentUser?.email ?? 'Compte Admin'
                      : null,
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
