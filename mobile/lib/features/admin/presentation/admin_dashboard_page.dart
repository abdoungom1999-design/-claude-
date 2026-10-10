import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/notifications/notifications_push.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/onyx_vert.dart';
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
  const AdminDashboardPage({super.key, this.notificationsPush, this.monUid});

  /// Injectables pour les tests ; par défaut, ceux de l'application.
  final NotificationsPush? notificationsPush;
  final String? monUid;

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
    _activerNotificationsPush();
  }

  /// Alertes de l'Admin (sauvegardes de la base à vérifier...) : cet appareil
  /// enregistre son jeton, comme ceux des clients et des chauffeurs. Sur le
  /// site, l'autorisation se donne avec le bouton de Paramètres (règle des
  /// navigateurs). La déconnexion supprime le jeton.
  void _activerNotificationsPush() {
    final uid = widget.monUid ?? _uidConnecte();
    if (uid == null) return;
    unawaited((widget.notificationsPush ?? NotificationsPush.instance).activer(uid: uid, surAppui: (_) {}));
  }

  static String? _uidConnecte() {
    if (!DefaultFirebaseOptions.estConfigure) return null;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
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
    // Charte Onyx & Vert, sans flou : tableau de bord dense (tableaux, listes).
    return EcranOnyxVert(
      flou: false,
      child: Scaffold(
      backgroundColor: Colors.transparent,
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
      ),
    );
  }
}
