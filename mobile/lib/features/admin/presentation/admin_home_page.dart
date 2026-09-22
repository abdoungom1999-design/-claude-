import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/network_error_view.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conducteurs'),
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
            : _erreurChargement != null
            ? NetworkErrorView(message: _erreurChargement!, onRetry: _charger)
            : _conducteurs.isEmpty
            ? const Center(
                child: Text(
                  'Aucun conducteur à afficher',
                  style: TextStyle(color: AppColors.grey),
                ),
              )
            : RefreshIndicator(
                onRefresh: _charger,
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _conducteurs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final conducteur = _conducteurs[index];
                    return _ConducteurCard(
                      conducteur: conducteur,
                      enCours: _enCours.contains(conducteur.id),
                      onValider: () => _valider(conducteur),
                      onRejeter: () => _rejeter(conducteur),
                    );
                  },
                ),
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

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.greyLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_outline, color: AppColors.grey),
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
              StatusBadge(
                label: conducteur.estValide ? 'Validé' : 'En attente',
                tone: conducteur.estValide
                    ? StatusTone.actif
                    : StatusTone.attention,
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
