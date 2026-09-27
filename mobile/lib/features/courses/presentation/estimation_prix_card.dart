import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/app_card.dart';
import '../data/estimation_course_controller.dart';

/// Encart "Prix estimé" des écrans Passager et Colis, piloté par
/// [EstimationCourseController] : consigne tant que les adresses
/// manquent, calcul en cours, prix en grand, ou erreur avec "Réessayer".
class EstimationPrixCard extends StatelessWidget {
  const EstimationPrixCard({super.key, required this.controller});

  final EstimationCourseController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => AppCard(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: switch (controller.etat) {
            EtatEstimation.adressesManquantes => const _Consigne(),
            EtatEstimation.calcul => const _Calcul(),
            EtatEstimation.prete => _Prix(controller: controller),
            EtatEstimation.erreur => _Erreur(controller: controller),
          },
        ),
      ),
    );
  }
}

class _Consigne extends StatelessWidget {
  const _Consigne();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.payments_outlined, color: AppColors.grey),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            "Choisissez l'adresse de départ et d'arrivée dans les suggestions pour voir le prix.",
            style: TextStyle(fontSize: 13, color: AppColors.grey, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _Calcul extends StatelessWidget {
  const _Calcul();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange),
          ),
          SizedBox(width: 12),
          Text('Calcul du prix…', style: TextStyle(color: AppColors.grey, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Prix extends StatelessWidget {
  const _Prix({required this.controller});

  final EstimationCourseController controller;

  @override
  Widget build(BuildContext context) {
    final estimation = controller.estimation!;
    final distance = (controller.distanceKm ?? estimation.distanceKm).toStringAsFixed(1).replaceAll('.', ',');
    final majoration = estimation.multiplicateurTrafic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Prix estimé', style: TextStyle(color: AppColors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          '~${formaterFcfa(estimation.prixFcfa)}',
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppColors.orange, height: 1.1),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _Pastille(icone: Icons.route_outlined, texte: '≈ $distance km'),
            _Pastille(icone: Icons.schedule_rounded, texte: '≈ ${estimation.dureeEstimeeMin} min'),
            if (majoration > 1)
              _Pastille(
                icone: Icons.trending_up_rounded,
                texte: '${majoration >= 1.4 ? 'Heure de pointe' : 'Tarif de nuit'} ×${majoration.toStringAsFixed(1).replaceAll('.', ',')}',
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            Icon(Icons.verified_user_outlined, size: 16, color: AppColors.vert),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Montant réglé à la commande, sans supplément à l\'arrivée.',
                style: TextStyle(fontSize: 12, color: AppColors.grey),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.icone, required this.texte});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: AppColors.greyLight, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: AppColors.grey),
          const SizedBox(width: 5),
          Text(texte, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Erreur extends StatelessWidget {
  const _Erreur({required this.controller});

  final EstimationCourseController controller;

  @override
  Widget build(BuildContext context) {
    final memeAdresse = (controller.distanceKm ?? 1) < EstimationCourseController.distanceMinimaleKm;
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            controller.erreur ?? "Le prix de ce trajet n'a pas pu être calculé.",
            style: TextStyle(fontSize: 13, color: Colors.red.shade700, height: 1.4),
          ),
        ),
        if (!memeAdresse)
          TextButton(
            onPressed: controller.reessayer,
            child: const Text('Réessayer', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.orange)),
          ),
      ],
    );
  }
}
