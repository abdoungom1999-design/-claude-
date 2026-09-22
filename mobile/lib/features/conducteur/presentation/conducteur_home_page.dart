import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/location/device_location_service.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/network_error_view.dart';
import '../../../core/widgets/online_toggle_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/trip_map.dart';
import '../../auth/data/auth_repository.dart';
import '../data/conducteur_repository.dart';

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
      appBar: AppBar(
        title: const Text('Tableau de bord'),
        actions: [
          IconButton(
            onPressed: _seDeconnecter,
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
          ),
        ],
      ),
      body: SafeArea(
        child: _chargement
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.orange),
              )
            : _profil == null
            ? NetworkErrorView(
                message: _erreurChargement ?? 'Impossible de charger le profil',
                onRetry: _chargerProfil,
              )
            : _contenu(_profil!),
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
        const Row(
          children: [
            Expanded(
              child: _StatTile(label: 'Courses aujourd\'hui', valeur: '0'),
            ),
            SizedBox(width: 12),
            Expanded(child: _StatTile(label: 'Gains estimés', valeur: '0 FCFA')),
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

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.valeur});

  final String label;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            valeur,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.grey)),
        ],
      ),
    );
  }
}
