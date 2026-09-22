import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dashboard_header.dart';
import '../../../core/widgets/network_error_view.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/data/auth_repository.dart';
import '../data/admin_repository.dart';

/// Interface Admin de gestion des conducteurs, connectée à l'API :
/// chargement de la vraie liste, actions Valider/Rejeter appelant les
/// endpoints correspondants.
class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  final _adminRepository = AdminRepository();
  final _authRepository = AuthRepository();

  List<ConducteurAdmin> _conducteurs = [];
  bool _chargement = true;
  String? _erreurChargement;
  final Set<String> _enCours = {};

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreurChargement = null;
    });
    try {
      final conducteurs = await _adminRepository.listerConducteurs();
      if (!mounted) return;
      setState(() => _conducteurs = conducteurs);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erreurChargement = e.message);
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _valider(ConducteurAdmin conducteur) async {
    setState(() => _enCours.add(conducteur.id));
    try {
      await _adminRepository.validerConducteur(conducteur.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${conducteur.nom} a été validé(e)')));
      await _charger();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enCours.remove(conducteur.id));
    }
  }

  Future<void> _rejeter(ConducteurAdmin conducteur) async {
    setState(() => _enCours.add(conducteur.id));
    try {
      await _adminRepository.rejeterConducteur(conducteur.id);
      if (!mounted) return;
      setState(() => _conducteurs.removeWhere((c) => c.id == conducteur.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${conducteur.nom} a été rejeté(e)')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enCours.remove(conducteur.id));
    }
  }

  Future<void> _seDeconnecter() async {
    await _authRepository.deconnecter();
    if (mounted) context.go(AppRoutes.espacePro);
  }

  @override
  Widget build(BuildContext context) {
    final enAttente = _conducteurs.where((c) => !c.estValide).length;
    final enLigne = _conducteurs.where((c) => c.statut == 'EN_LIGNE').length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            DashboardHeader(
              title: 'Espace Admin',
              subtitle: 'Gestion des conducteurs Sprint',
              onDeconnexion: _seDeconnecter,
            ),
            Expanded(
              child: _chargement
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.orange),
                    )
                  : _erreurChargement != null
                  ? NetworkErrorView(
                      message: _erreurChargement!,
                      onRetry: _charger,
                    )
                  : RefreshIndicator(
                      onRefresh: _charger,
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: StatTile(
                                  label: 'Conducteurs',
                                  valeur: '${_conducteurs.length}',
                                  icon: Icons.groups_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: StatTile(
                                  label: 'En attente',
                                  valeur: '$enAttente',
                                  icon: Icons.hourglass_top_rounded,
                                  accent: Colors.amber.shade700,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: StatTile(
                                  label: 'En ligne',
                                  valeur: '$enLigne',
                                  icon: Icons.bolt_rounded,
                                  accent: Colors.green.shade600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Tous les conducteurs',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_conducteurs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 40),
                              child: Center(
                                child: Text(
                                  'Aucun conducteur à afficher',
                                  style: TextStyle(color: AppColors.grey),
                                ),
                              ),
                            )
                          else
                            ..._conducteurs.map(
                              (conducteur) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _ConducteurCard(
                                  conducteur: conducteur,
                                  enCours: _enCours.contains(conducteur.id),
                                  onValider: () => _valider(conducteur),
                                  onRejeter: () => _rejeter(conducteur),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConducteurCard extends StatelessWidget {
  const _ConducteurCard({
    required this.conducteur,
    required this.enCours,
    required this.onValider,
    required this.onRejeter,
  });

  final ConducteurAdmin conducteur;
  final bool enCours;
  final VoidCallback onValider;
  final VoidCallback onRejeter;

  String get _initiales {
    final mots = conducteur.nom.trim().split(RegExp(r'\s+'));
    if (mots.isEmpty) return '?';
    final premiere = mots.first.isNotEmpty ? mots.first[0] : '';
    final derniere = mots.length > 1 && mots.last.isNotEmpty ? mots.last[0] : '';
    return '$premiere$derniere'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.orange, AppColors.orangeDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initiales,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conducteur.nom,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${conducteur.telephone} · '
                      '${conducteur.vehiculeId ?? 'Véhicule non renseigné'}',
                      style: const TextStyle(fontSize: 12, color: AppColors.grey),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusBadge(
                    label: conducteur.estValide ? 'Validé' : 'En attente',
                    tone: conducteur.estValide
                        ? StatusTone.actif
                        : StatusTone.attention,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: conducteur.statut == 'EN_LIGNE'
                              ? Colors.green.shade600
                              : AppColors.greyBorder,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        conducteur.statut == 'EN_LIGNE'
                            ? 'En ligne'
                            : 'Hors ligne',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          if (!conducteur.estValide) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Rejeter',
                    onPressed: enCours ? null : onRejeter,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: 'Valider',
                    isLoading: enCours,
                    onPressed: enCours ? null : onValider,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
