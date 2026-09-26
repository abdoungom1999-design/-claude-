import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../courses/data/course_service.dart';

/// Bandeau de la course en cours du chauffeur, affiché au-dessus de la
/// barre de navigation tant qu'une course lui est attribuée. Un seul
/// bouton, qui fait avancer la course : "Client à bord" (`acceptee` ->
/// `en_cours`), puis "Terminer la course" (`en_cours` -> `terminee`).
class CourseActiveBandeau extends StatelessWidget {
  const CourseActiveBandeau({
    super.key,
    required this.course,
    required this.enCours,
    required this.onAvancer,
  });

  final CourseFirestore course;

  /// Mise à jour Firestore en cours : bouton désactivé.
  final bool enCours;
  final VoidCallback onAvancer;

  bool get _clientABord => course.statut == StatutCourse.enCours;

  @override
  Widget build(BuildContext context) {
    final colis = course.type == 'COLIS';
    return Material(
      color: AppColors.orange,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Icon(
                colis ? Icons.inventory_2_outlined : Icons.two_wheeler_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _clientABord
                          ? (colis ? 'Livraison en cours' : 'Course en cours')
                          : (colis ? 'Récupérez le colis' : 'Rejoignez votre client'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _clientABord ? 'Vers ${course.adresseArrivee}' : 'Départ : ${course.adresseDepart}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: enCours ? null : onAvancer,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.orange,
                  disabledBackgroundColor: Colors.white70,
                ),
                child: enCours
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange),
                      )
                    : Text(
                        _clientABord ? 'Terminer la course' : (colis ? 'Colis récupéré' : 'Client à bord'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
