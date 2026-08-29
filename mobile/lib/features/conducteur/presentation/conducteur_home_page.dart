import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/demo_coordinates.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/network_error_view.dart';
import '../../../core/widgets/online_toggle_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/data/auth_repository.dart';
import '../data/conducteur_repository.dart';

/// Tableau de bord Conducteur, connecté à l'API : profil réel, bascule
/// En Ligne/Hors Ligne, et envoi périodique (toutes les 5s) d'une
/// position GPS simulée à Dakar tant que le conducteur est en ligne.
class ConducteurHomePage extends StatefulWidget {
  const ConducteurHomePage({super.key});

  @override
  State<ConducteurHomePage> createState() => _ConducteurHomePageState();
}

class _ConducteurHomePageState extends State<ConducteurHomePage> {
  final _conducteurRepository = ConducteurRepository();
  final _authRepository = AuthRepository();

  ProfilConducteur? _profil;
  bool _chargement = true;
  String? _erreurChargement;
  bool _enLigne = false;
  Timer? _minuteurPosition;
  int _tick = 0;
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
    _tick = 0;
    _envoyerPositionSimulee();
    _minuteurPosition = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _envoyerPositionSimulee(),
    );
  }

  void _arreterEnvoiPosition() {
    _minuteurPosition?.cancel();
    _minuteurPosition = null;
  }

  /// Simule un déplacement autour du Plateau (Dakar) tant qu'aucun GPS
  /// réel n'est branché (voir MapPlaceholder, Phase 3).
  Future<void> _envoyerPositionSimulee() async {
    _tick++;
    final angle = _tick * 0.3;
    final latitude = DemoCoordinates.plateauLatitude + 0.01 * math.sin(angle);
    final longitude =
        DemoCoordinates.plateauLongitude + 0.01 * math.cos(angle);
    try {
      await _conducteurRepository.mettreAJourPosition(
        latitude: latitude,
        longitude: longitude,
      );
      if (mounted) setState(() => _dernierEnvoiPosition = DateTime.now());
    } on ApiException catch (_) {
      // Échec silencieux : la prochaine tentative aura lieu au tick suivant,
      // sans interrompre l'expérience du conducteur en ligne.
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
        if (_enLigne && _dernierEnvoiPosition != null) ...[
          const SizedBox(height: 8),
          Text(
            'Position envoyée à '
            '${_dernierEnvoiPosition!.hour.toString().padLeft(2, '0')}:'
            '${_dernierEnvoiPosition!.minute.toString().padLeft(2, '0')}:'
            '${_dernierEnvoiPosition!.second.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 12, color: AppColors.grey),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _StatTile(label: 'Courses aujourd\'hui', valeur: '0'),
            ),
            const SizedBox(width: 12),
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
                      style: TextStyle(fontSize: 12, color: AppColors.grey),
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
          Text(label, style: TextStyle(fontSize: 12, color: AppColors.grey)),
        ],
      ),
    );
  }
}
