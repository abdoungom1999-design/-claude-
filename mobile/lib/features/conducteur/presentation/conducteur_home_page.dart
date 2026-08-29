import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/online_toggle_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../../core/widgets/status_badge.dart';

/// Tableau de bord Conducteur. Données d'exemple uniquement : aucune
/// connexion API à ce stade (Phase 3 = design seul).
class ConducteurHomePage extends StatefulWidget {
  const ConducteurHomePage({super.key});

  @override
  State<ConducteurHomePage> createState() => _ConducteurHomePageState();
}

class _ConducteurHomePageState extends State<ConducteurHomePage> {
  bool _enLigne = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tableau de bord')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            OnlineToggleButton(
              enLigne: _enLigne,
              onChanged: (valeur) => setState(() => _enLigne = valeur),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Courses aujourd\'hui',
                    valeur: '0',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(label: 'Gains estimés', valeur: '0 FCFA'),
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bajaj Boxer',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Véhicule enregistré',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const StatusBadge(
                    label: 'En attente de validation',
                    tone: StatusTone.attention,
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
        ),
      ),
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
