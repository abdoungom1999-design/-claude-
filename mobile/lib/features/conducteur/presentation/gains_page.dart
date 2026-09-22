import 'package:flutter/material.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/stat_tile.dart';

/// Récapitulatif des gains du conducteur.
class GainsPage extends StatelessWidget {
  const GainsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gains')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.noirProfond, AppColors.noirProfondClair],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gains ce mois-ci',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '${DemoData.gainsMoisFcfa} FCFA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Aujourd\'hui',
                    valeur: '${DemoData.gainsEstimesFcfa} FCFA',
                    icon: Icons.today_outlined,
                    accent: Colors.green.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: StatTile(
                    label: 'Cette semaine',
                    valeur: '${DemoData.gainsSemaineFcfa} FCFA',
                    icon: Icons.calendar_view_week_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Courses (semaine)',
                    valeur: '${DemoData.coursesSemaine}',
                    icon: Icons.route_outlined,
                    accent: Colors.blueGrey,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    label: 'Courses (aujourd\'hui)',
                    valeur: '${DemoData.coursesAujourdHui}',
                    icon: Icons.two_wheeler_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            AppCard(
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.orangeLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.orange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Les paiements sont versés automatiquement sur votre '
                      'compte Wave ou Orange Money chaque semaine.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.grey),
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
