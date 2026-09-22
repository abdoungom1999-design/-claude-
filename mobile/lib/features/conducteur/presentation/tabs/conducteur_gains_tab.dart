import 'package:flutter/material.dart';
import '../../../../core/demo/demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../widgets/gains_barres_chart.dart';

/// Onglet Gains : gros en-tête gains de la semaine, graphique à barres
/// par jour, 10 dernières courses terminées.
class ConducteurGainsTab extends StatelessWidget {
  const ConducteurGainsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final courses = DemoData.coursesTermineesConducteur();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Gains',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.noirProfond, AppColors.noirProfondClair],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gains cette semaine',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '${DemoData.gainsSemaineFcfa} FCFA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${DemoData.coursesSemaine} courses effectuées',
                    style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const AppCard(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Revenus par jour',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 18),
                  GainsBarresChart(
                    valeurs: DemoData.gainsParJourSemaine,
                    labels: DemoData.joursSemaineCourts,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '10 dernières courses',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < courses.length; i++) ...[
                    _LigneCourseGains(course: courses[i]),
                    if (i != courses.length - 1)
                      const Divider(height: 1, color: AppColors.greyBorder),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LigneCourseGains extends StatelessWidget {
  const _LigneCourseGains({required this.course});

  final CourseTermineeConducteur course;

  @override
  Widget build(BuildContext context) {
    final estColis = course.type == 'Colis';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.greyLight,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              estColis ? Icons.inventory_2_outlined : Icons.two_wheeler_rounded,
              color: AppColors.grey,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(course.type, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                Text(
                  course.heure,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                ),
              ],
            ),
          ),
          Text(
            '+${course.montantFcfa} FCFA',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: AppColors.vert,
            ),
          ),
        ],
      ),
    );
  }
}
