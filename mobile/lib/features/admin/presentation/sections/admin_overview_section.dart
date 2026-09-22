import 'package:flutter/material.dart';
import '../../../../core/demo/admin_demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../widgets/admin_courbe_courses.dart';
import '../widgets/admin_kpi_card.dart';

/// Page "Dashboard" (vue d'ensemble) de la Tour de Contrôle : KPIs du
/// jour, courbe hebdomadaire, dernières courses.
class AdminOverviewSection extends StatelessWidget {
  const AdminOverviewSection({super.key});

  @override
  Widget build(BuildContext context) {
    final caFormate = _formaterFcfa(AdminDemoData.caJourFcfa);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: AdminKpiCard(
                icon: Icons.payments_outlined,
                valeur: '$caFormate FCFA',
                label: 'Chiffre d\'affaires du jour',
              ),
            ),
            const SizedBox(width: 18),
            const Expanded(
              child: AdminKpiCard(
                icon: Icons.task_alt_rounded,
                valeur: '${AdminDemoData.coursesTermineesJour}',
                label: 'Courses terminées',
                accent: AppColors.vert,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: AdminKpiCard(
                icon: Icons.two_wheeler_rounded,
                valeur: '${AdminDemoData.chauffeursEnLigne}',
                label: 'Chauffeurs en ligne',
                accent: AppColors.or,
              ),
            ),
            const SizedBox(width: 18),
            const Expanded(
              child: AdminKpiCard(
                icon: Icons.person_add_alt_1_rounded,
                valeur: '${AdminDemoData.nouveauxInscritsJour}',
                label: 'Nouveaux inscrits',
                accent: AppColors.noirProfondClair,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const AppCard(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Évolution des courses cette semaine',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                'Nombre de courses terminées, par jour.',
                style: TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
              SizedBox(height: 20),
              AdminCourbeCourses(
                valeurs: AdminDemoData.courbeCoursesSemaine,
                labels: AdminDemoData.joursSemaineCourts,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dernières courses',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _TableauDernieresCourses(courses: AdminDemoData.dernieresCourses()),
            ],
          ),
        ),
      ],
    );
  }

  static String _formaterFcfa(int montant) {
    final chiffres = montant.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < chiffres.length; i++) {
      if (i > 0 && (chiffres.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(chiffres[i]);
    }
    return buffer.toString();
  }
}

class _TableauDernieresCourses extends StatelessWidget {
  const _TableauDernieresCourses({required this.courses});

  final List<CourseAdminRecap> courses;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _LigneTableau(
          entete: true,
          id: 'Course',
          client: 'Client',
          chauffeur: 'Chauffeur',
          trajet: 'Trajet',
          montant: 'Montant',
          statut: null,
        ),
        const Divider(height: 20, color: AppColors.greyBorder),
        for (final course in courses)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _LigneTableau(
              id: course.id,
              client: course.client,
              chauffeur: course.chauffeur,
              trajet: course.trajet,
              montant: '${course.montantFcfa} FCFA',
              statut: course.statut,
            ),
          ),
      ],
    );
  }
}

class _LigneTableau extends StatelessWidget {
  const _LigneTableau({
    required this.id,
    required this.client,
    required this.chauffeur,
    required this.trajet,
    required this.montant,
    required this.statut,
    this.entete = false,
  });

  final String id;
  final String client;
  final String chauffeur;
  final String trajet;
  final String montant;
  final StatutCourseAdmin? statut;
  final bool entete;

  TextStyle get _style => TextStyle(
    fontSize: entete ? 11.5 : 13,
    fontWeight: entete ? FontWeight.w700 : FontWeight.w500,
    color: entete ? AppColors.grey : AppColors.text,
    letterSpacing: entete ? 0.4 : 0,
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 70, child: Text(id, style: _style)),
        Expanded(flex: 2, child: Text(client, style: _style)),
        Expanded(flex: 2, child: Text(chauffeur, style: _style)),
        Expanded(flex: 3, child: Text(trajet, style: _style)),
        SizedBox(width: 90, child: Text(montant, style: _style)),
        SizedBox(
          width: 100,
          child: entete
              ? Text('Statut', style: _style)
              : _BadgeStatutCourse(statut: statut!),
        ),
      ],
    );
  }
}

class _BadgeStatutCourse extends StatelessWidget {
  const _BadgeStatutCourse({required this.statut});

  final StatutCourseAdmin statut;

  @override
  Widget build(BuildContext context) {
    final (label, couleur) = switch (statut) {
      StatutCourseAdmin.terminee => ('Terminée', AppColors.vert),
      StatutCourseAdmin.annulee => ('Annulée', Colors.redAccent),
      StatutCourseAdmin.enCours => ('En cours', AppColors.orange),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
