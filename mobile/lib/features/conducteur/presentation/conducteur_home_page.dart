import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/config/api_config.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/location/device_location_service.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dashboard_header.dart';
import '../../../core/widgets/network_error_view.dart';
import '../../../core/widgets/online_toggle_button.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/trip_map.dart';
import '../../auth/data/auth_repository.dart';
import '../../compte/presentation/centre_aide_page.dart';
import '../../messages/presentation/messages_tab_page.dart';
import '../data/conducteur_repository.dart';
import 'evaluations_page.dart';
import 'gains_page.dart';

/// Tableau de bord Conducteur, connecté à l'API : profil réel, bascule
/// En Ligne/Hors Ligne, et envoi périodique (toutes les 5s) de la
/// véritable position GPS de l'appareil tant que le conducteur est en
/// ligne. Nécessite les permissions de localisation natives (voir la
/// checklist de configuration fournie avec cette intégration).
class ConducteurHomePage extends StatefulWidget {
  const ConducteurHomePage({super.key});

  @override
  State<ConducteurHomePage> createState() => _ConducteurHomePageState();
}

class _ConducteurHomePageState extends State<ConducteurHomePage> {
  final _conducteurRepository = ConducteurRepository();
  final _authRepository = AuthRepository();
  final _locationService = DeviceLocationService();

  ProfilConducteur? _profil;
  bool _chargement = true;
  String? _erreurChargement;
  bool _enLigne = false;
  Timer? _minuteurPosition;
  LatLng? _dernierePosition;
  DateTime? _dernierEnvoiPosition;

  @override
  void initState() {
    super.initState();
    _chargerProfil();
  }

  @override
  void dispose() {
    _minuteurPosition?.cancel();
    super.dispose();
  }

  Future<void> _chargerProfil() async {
    setState(() {
      _chargement = true;
      _erreurChargement = null;
    });
    try {
      final profil = await _conducteurRepository.monProfil();
      if (!mounted) return;
      setState(() {
        _profil = profil;
        _enLigne = profil.statut == 'EN_LIGNE';
      });
      if (_enLigne) _demarrerEnvoiPosition();
    } on ApiException catch (e) {
      if (mounted) setState(() => _erreurChargement = e.message);
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _basculerStatut(bool vouloirEnLigne) async {
    if (vouloirEnLigne) {
      final autorise = await _locationService.permissionAccordee();
      if (!autorise) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Autorisez la localisation pour passer en ligne',
            ),
          ),
        );
        return;
      }
    }

    final nouveauStatut = vouloirEnLigne ? 'EN_LIGNE' : 'HORS_LIGNE';
    try {
      final statutConfirme = await _conducteurRepository.mettreAJourStatut(
        nouveauStatut,
      );
      if (!mounted) return;
      setState(() => _enLigne = statutConfirme == 'EN_LIGNE');
      if (_enLigne) {
        _demarrerEnvoiPosition();
      } else {
        _arreterEnvoiPosition();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _demarrerEnvoiPosition() {
    _minuteurPosition?.cancel();
    _envoyerPositionReelle();
    _minuteurPosition = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _envoyerPositionReelle(),
    );
  }

  void _arreterEnvoiPosition() {
    _minuteurPosition?.cancel();
    _minuteurPosition = null;
  }

  Future<void> _envoyerPositionReelle() async {
    try {
      final position = await _locationService.positionActuelle();
      await _conducteurRepository.mettreAJourPosition(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;
      setState(() {
        _dernierePosition = LatLng(position.latitude, position.longitude);
        _dernierEnvoiPosition = DateTime.now();
      });
    } catch (_) {
      // Échec silencieux (API ou GPS momentanément indisponible) : la
      // prochaine tentative aura lieu au tick suivant, sans interrompre
      // l'expérience du conducteur en ligne.
    }
  }

  Future<void> _seDeconnecter() async {
    _arreterEnvoiPosition();
    await _authRepository.deconnecter();
    if (mounted) context.go(AppRoutes.espacePro);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: _ConducteurDrawer(
        profil: _profil,
        enLigne: _enLigne,
        onChangerStatut: _basculerStatut,
        onDeconnexion: _seDeconnecter,
      ),
      body: SafeArea(
        child: Column(
          children: [
            DashboardHeader(
              title: 'Tableau de bord',
              subtitle: 'Espace Conducteur Sprint',
              onDeconnexion: _seDeconnecter,
              leading: Builder(
                builder: (context) => InkWell(
                  onTap: () => Scaffold.of(context).openDrawer(),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.menu_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _chargement
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.orange),
                    )
                  : _profil == null
                  ? NetworkErrorView(
                      message:
                          _erreurChargement ?? 'Impossible de charger le profil',
                      onRetry: _chargerProfil,
                    )
                  : _contenu(_profil!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenu(ProfilConducteur profil) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        OnlineToggleButton(enLigne: _enLigne, onChanged: _basculerStatut),
        if (_enLigne && _dernierePosition != null) ...[
          const SizedBox(height: 16),
          TripMap(depart: _dernierePosition, height: 180),
          if (_dernierEnvoiPosition != null) ...[
            const SizedBox(height: 8),
            Text(
              'Position envoyée à '
              '${_dernierEnvoiPosition!.hour.toString().padLeft(2, '0')}:'
              '${_dernierEnvoiPosition!.minute.toString().padLeft(2, '0')}:'
              '${_dernierEnvoiPosition!.second.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 12, color: AppColors.grey),
            ),
          ],
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Courses aujourd\'hui',
                valeur: ApiConfig.modeDemo
                    ? '${DemoData.coursesAujourdHui}'
                    : '0',
                icon: Icons.route_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                label: 'Gains estimés',
                valeur: ApiConfig.modeDemo
                    ? '${DemoData.gainsEstimesFcfa} FCFA'
                    : '0 FCFA',
                icon: Icons.payments_outlined,
                accent: Colors.green.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        AppCard(
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.greyLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.two_wheeler_rounded,
                  color: AppColors.grey,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profil.nom,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      profil.vehiculeId ?? 'Véhicule non renseigné',
                      style: const TextStyle(fontSize: 12, color: AppColors.grey),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                label: profil.estValide ? 'Validé' : 'En attente de validation',
                tone: profil.estValide ? StatusTone.actif : StatusTone.attention,
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        SecondaryButton(
          label: 'Simuler une demande de course',
          icon: Icons.notifications_active_outlined,
          onPressed: () => context.push(AppRoutes.conducteurAlerteCourse),
        ),
      ],
    );
  }
}

class _ConducteurDrawer extends StatelessWidget {
  const _ConducteurDrawer({
    required this.profil,
    required this.enLigne,
    required this.onChangerStatut,
    required this.onDeconnexion,
  });

  final ProfilConducteur? profil;
  final bool enLigne;
  final ValueChanged<bool> onChangerStatut;
  final VoidCallback onDeconnexion;

  void _ouvrirPage(BuildContext context, Widget page) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _bientotDisponible(BuildContext context, String label) {
    Navigator.of(context).pop();
    PremiumDialog.bientotDisponible(context, label);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
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
                      profil?.nom.isNotEmpty == true
                          ? profil!.nom[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profil?.nom ?? 'Conducteur',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                      SizedBox(width: 4),
                      Text(
                        '${DemoData.noteMoyenneConducteur}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: enLigne
                          ? Colors.green.withValues(alpha: 0.1)
                          : AppColors.greyLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            enLigne ? 'En ligne · ACTIF' : 'Hors ligne',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: enLigne
                                  ? Colors.green.shade700
                                  : AppColors.grey,
                            ),
                          ),
                        ),
                        Switch(
                          value: enLigne,
                          onChanged: onChangerStatut,
                          activeThumbColor: Colors.green.shade600,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _ItemMenu(
                    icon: Icons.home_outlined,
                    label: 'Accueil',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  _ItemMenu(
                    icon: Icons.assignment_outlined,
                    label: 'Missions',
                    onTap: () => _bientotDisponible(context, 'Missions'),
                  ),
                  _ItemMenu(
                    icon: Icons.payments_outlined,
                    label: 'Gains',
                    onTap: () => _ouvrirPage(context, const GainsPage()),
                  ),
                  _ItemMenu(
                    icon: Icons.star_border_rounded,
                    label: 'Évaluations',
                    onTap: () => _ouvrirPage(context, const EvaluationsPage()),
                  ),
                  _ItemMenu(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Messages',
                    badge: '2',
                    onTap: () => _ouvrirPage(context, const MessagesTabPage()),
                  ),
                  _ItemMenu(
                    icon: Icons.help_outline_rounded,
                    label: 'Centre d\'aide',
                    onTap: () => _ouvrirPage(context, const CentreAidePage()),
                  ),
                  _ItemMenu(
                    icon: Icons.settings_outlined,
                    label: 'Paramètres',
                    onTap: () => _bientotDisponible(context, 'Paramètres'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _ItemMenu(
              icon: Icons.logout_rounded,
              label: 'Se déconnecter',
              onTap: onDeconnexion,
            ),
            const SizedBox(height: 8),
          ],
        ),
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
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      trailing: badge != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
