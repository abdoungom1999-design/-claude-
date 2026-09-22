import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';
import 'receipts_page.dart';

/// Onglet Activité : bascule Course immédiate / Livraison / Réservations,
/// état vide avec appel à l'action, historique récent et accès aux reçus.
class ActiviteTabPage extends StatelessWidget {
  const ActiviteTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Activité',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const TabBar(
                labelColor: AppColors.orange,
                unselectedLabelColor: AppColors.grey,
                indicatorColor: AppColors.orange,
                labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                tabs: [
                  Tab(text: 'Course immédiate'),
                  Tab(text: 'Livraison'),
                  Tab(text: 'Réservations'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _OngletActivite(
                      typeFiltre: 'PASSAGER',
                      labelCta: 'Commander une course',
                      onCta: () => context.push(AppRoutes.clientPassager),
                    ),
                    _OngletActivite(
                      typeFiltre: 'COLIS',
                      labelCta: 'Envoyer un colis',
                      onCta: () => context.push(AppRoutes.clientColis),
                    ),
                    _OngletActivite(
                      typeFiltre: null,
                      labelCta: 'Découvrir les réservations',
                      onCta: () =>
                          PremiumDialog.bientotDisponible(context, 'Réservations'),
                      aucuneDonneePossible: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OngletActivite extends StatelessWidget {
  const _OngletActivite({
    required this.typeFiltre,
    required this.labelCta,
    required this.onCta,
    this.aucuneDonneePossible = false,
  });

  /// null pour "Réservations" : aucune course historique ne correspond,
  /// la fonctionnalité n'existe pas encore côté modèle de données.
  final String? typeFiltre;
  final String labelCta;
  final VoidCallback onCta;
  final bool aucuneDonneePossible;

  @override
  Widget build(BuildContext context) {
    final historique = aucuneDonneePossible
        ? const <CourseHistorique>[]
        : DemoData.historique(type: typeFiltre);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        AppCard(
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.greyLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_taxi_outlined,
                  color: AppColors.grey,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Aucune course en cours',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                aucuneDonneePossible
                    ? 'Les réservations à l\'avance arrivent bientôt'
                    : 'Vos courses en cours apparaîtront ici',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
              const SizedBox(height: 16),
              PrimaryButton(label: labelCta, onPressed: onCta),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Historique récent',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReceiptsPage()),
              ),
              child: const Text('Reçus'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (historique.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'Aucun historique pour le moment',
                style: TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
            ),
          )
        else
          ...historique.map(
            (course) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CarteHistorique(course: course),
            ),
          ),
      ],
    );
  }
}

class _CarteHistorique extends StatelessWidget {
  const _CarteHistorique({required this.course});

  final CourseHistorique course;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              course.type == 'COLIS'
                  ? Icons.inventory_2_outlined
                  : Icons.two_wheeler_rounded,
              color: AppColors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${course.adresseDepart} → ${course.adresseArrivee}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '${course.statut} · ${course.date.day.toString().padLeft(2, '0')}/'
                  '${course.date.month.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                ),
              ],
            ),
          ),
          Text(
            '${course.prixFcfa} FCFA',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
